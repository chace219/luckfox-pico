#!/bin/bash
# Gate for the oem partition payload — CRA Annex I Part I #4 (minimise attack
# surface), plan item 14.
#
# WHAT IT DEFENDS. build.sh's __PACKAGE_RESOURCES fills the oem staging
# directory from the BSP's media/app output with no notion of what the product
# runs. Left alone it packs 198 files / 21 MB onto a shipped device: rkipc and
# ~60 sample_*/rk_*_test binaries, the camera pipeline libraries, the AIC8800
# Wi-Fi driver and its firmware, sensor and ISP modules, and a second divergent
# copy of the SATISense console. Nothing on this product reads any of it.
#
# WHY IT IS A GATE AND NOT A REVIEW. The payload is not written down anywhere —
# it is whatever the media and app trees happened to install, so it grows
# silently with the BSP. Nothing in the build fails when it does, and the
# result is invisible in the rootfs: the SBOM describes the rootfs, `./build.sh
# cve` scans the rootfs, and every ownership and hardening check before this one
# looked at the rootfs. The oem partition had never been asserted about at all,
# which is how a stale console bundle and a Wi-Fi driver stayed on a product
# whose Wi-Fi was removed from the build in August.
#
# It is also the partition the A/B updater cannot write, so anything that lands
# there is beyond the reach of every future fix. That is the reason the two
# modules the product does use are RESCUED INTO THE ROOTFS rather than kept.
#
# Source-level, so it runs on a clean checkout; the image checks additionally
# apply when a build is present.
#
# Usage: check-oem-payload.sh [--verbose]
set -u
cd "$(dirname "$0")/../.." || exit 2

# The board profiles that ship as Joral products. Both must strip oem; the
# other 14 configs are BSP boards whose whole function IS the oem payload.
JORAL_CFGS=(
	project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk
	project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC-AB.mk
)
OEM_HOOK=project/cfg/BoardConfig_IPC/luckfox-joral-oem-pre.sh
OVERLAY=project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/etc/init.d
RGB_OVERLAY=project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-rgb/etc/init.d
DTS=sysdrv/source/kernel/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra.dts
IMAGEDIR=${OEM_IMAGEDIR:-output/image}

# The only modules the product uses, and the only ones the hook may rescue.
# Adding one here is a decision to carry a kernel module in the rootfs; it must
# be matched in the hook, and something must load it.
KEEP_MODULES=(rknpu.ko pwm_bl.ko)

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

pass=0; fail=0
ok()   { echo "ok   — $1"; pass=$((pass+1)); }
bad()  { echo "FAIL — $1"; fail=$((fail+1)); }
skip() { echo "skip — $1"; }
note() { [ $VERBOSE -eq 1 ] && echo "       $1"; return 0; }

echo "== Board profiles select the stripping hook"
for cfg in "${JORAL_CFGS[@]}"; do
	if [ ! -f "$cfg" ]; then
		bad "$cfg is missing"
		continue
	fi
	if grep -q '^export RK_PRE_BUILD_OEM_SCRIPT=luckfox-joral-oem-pre.sh$' "$cfg"; then
		ok "$(basename "$cfg") selects luckfox-joral-oem-pre.sh"
	else
		bad "$(basename "$cfg") does not select luckfox-joral-oem-pre.sh — its oem payload would ship"
	fi
done

echo
echo "== The hook empties the payload and rescues only the declared modules"
if [ ! -f "$OEM_HOOK" ]; then
	bad "$OEM_HOOK is missing"
else
	hook_keep=$(sed -n 's/^KEEP_MODULES="\(.*\)"$/\1/p' "$OEM_HOOK")
	if [ -z "$hook_keep" ]; then
		bad "$OEM_HOOK does not declare KEEP_MODULES"
	elif [ "$hook_keep" = "${KEEP_MODULES[*]}" ]; then
		ok "hook rescues exactly: $hook_keep"
	else
		bad "hook rescues '$hook_keep', this gate expects '${KEEP_MODULES[*]}'"
	fi

	# The emptiness assertion is the hook's own last line of defence. A hook
	# that deletes but does not assert would silently degrade the day the BSP
	# stages a file the delete misses.
	if grep -q 'assert_empty' "$OEM_HOOK"; then
		ok "hook asserts the payload is empty before the image is packed"
	else
		bad "hook does not assert emptiness — a partial strip would pack silently"
	fi
fi

echo
echo "== The runtime half ships, so fielded units are cleaned too"
if [ -x "$OVERLAY/S22oemclean" ]; then
	ok "S22oemclean is in the shared init overlay"
	if grep -q 'MOUNTS_FILE' "$OVERLAY/S22oemclean" && grep -q '/proc/mounts' "$OVERLAY/S22oemclean"; then
		ok "S22oemclean gates on /proc/mounts, not on the mountpoint existing"
	else
		bad "S22oemclean does not gate on /proc/mounts — it would purge an unmounted mountpoint and report success"
	fi
	if grep -q 'chown 0:0' "$OVERLAY/S22oemclean"; then
		ok "S22oemclean re-owns the pre-2026-08-15 uid-1000 mountpoint"
	else
		bad "S22oemclean does not re-own /oem — the ownership defect would survive on fielded units"
	fi
else
	bad "$OVERLAY/S22oemclean missing or not executable"
fi

echo
echo "== The NPU is actually reachable, not just present"
if [ -x "$OVERLAY/S52npu" ]; then
	ok "S52npu is in the shared init overlay"
	if grep -q 'uname -r' "$OVERLAY/S52npu"; then
		ok "S52npu resolves the module under the running kernel release"
	else
		bad "S52npu uses a fixed module path — a kernel/rootfs drift would fail inside insmod instead of being reported"
	fi
else
	bad "$OVERLAY/S52npu missing or not executable"
fi
if [ -f "$DTS" ]; then
	# The loader is useless while the node is disabled: the driver registers
	# /dev/rknpu from probe(), and probe never runs on a disabled node. This is
	# the check that stops the fix from being half-applied.
	if awk '/^&npu \{/{n=1} n&&/status *= *"okay"/{found=1} n&&/^};/{n=0} END{exit !found}' "$DTS"; then
		ok "the npu device-tree node is enabled for the Pico Ultra"
	else
		bad "$DTS does not enable &npu — rknpu.ko would load and never probe"
	fi
else
	bad "$DTS is missing"
fi
if [ -x "$RGB_OVERLAY/S25backlight" ]; then
	if grep -q 'lib/modules' "$RGB_OVERLAY/S25backlight"; then
		ok "S25backlight prefers the rootfs copy of pwm_bl.ko"
	else
		bad "S25backlight still loads pwm_bl.ko from /oem only — it would break on a stripped image"
	fi
else
	bad "$RGB_OVERLAY/S25backlight missing or not executable"
fi

echo
echo "== The packed images agree (build present)"
if [ -f "$IMAGEDIR/oem.img" ] && command -v debugfs >/dev/null 2>&1; then
	# One listing of / is enough to prove emptiness: every payload directory
	# the BSP stages (usr/) hangs off the root, so a surviving file cannot hide
	# below a directory that is itself absent from this listing.
	entries=$(debugfs -R "ls -p /" "$IMAGEDIR/oem.img" 2>/dev/null |
		awk -F/ 'NF>3 {print $6}' | grep -v '^$' | grep -vx '\.' | grep -vx '\.\.' | grep -vx 'lost+found')
	if [ -z "$entries" ]; then
		ok "oem.img carries no payload"
	else
		bad "oem.img still carries: $(echo "$entries" | tr '\n' ' ')"
	fi
	note "oem.img size: $(du -h "$IMAGEDIR/oem.img" | cut -f1)"
else
	skip "oem.img — no build present, or debugfs unavailable"
fi

if [ -f "$IMAGEDIR/rootfs.img" ] && command -v debugfs >/dev/null 2>&1; then
	krel=$(debugfs -R "ls -p /lib/modules" "$IMAGEDIR/rootfs.img" 2>/dev/null |
		awk -F/ 'NF>3 {print $6}' | grep -vx '\.' | grep -vx '\.\.' | grep -v '^$' | head -n1)
	if [ -z "$krel" ]; then
		bad "rootfs.img has no /lib/modules/<release> — the rescued modules did not land"
	else
		note "module directory: /lib/modules/$krel"
		for ko in "${KEEP_MODULES[@]}"; do
			if debugfs -R "stat /lib/modules/$krel/$ko" "$IMAGEDIR/rootfs.img" 2>/dev/null | grep -q 'Inode:'; then
				ok "rootfs.img carries /lib/modules/$krel/$ko"
			else
				bad "rootfs.img is missing /lib/modules/$krel/$ko"
			fi
		done
	fi

	# Files a previous release shipped and this one must not. post_overlay's
	# rsync has no --delete and the staging rootfs is reused, so a renamed
	# overlay file survives into every later image until something removes it —
	# found on a unit 2026-08-21, where S23npu and S52npu BOTH shipped and the
	# old one won by running first.
	for s in S23npu; do
		if debugfs -R "stat /etc/init.d/$s" "$IMAGEDIR/rootfs.img" 2>/dev/null | grep -q 'Inode:'; then
			bad "rootfs.img still carries the superseded /etc/init.d/$s — the rename did not reach the image"
		else
			ok "no superseded /etc/init.d/$s in rootfs.img"
		fi
	done

	for s in S22oemclean S52npu; do
		if debugfs -R "stat /etc/init.d/$s" "$IMAGEDIR/rootfs.img" 2>/dev/null | grep -q 'Inode:'; then
			ok "rootfs.img carries /etc/init.d/$s"
		else
			bad "rootfs.img is missing /etc/init.d/$s"
		fi
	done

	# The symlink __PACKAGE_OEM leaves behind when it staged ISP tuning files.
	# With the payload gone it points at nothing, and a dangling symlink in
	# /etc reads as a failed install rather than a deliberate removal.
	if debugfs -R "stat /etc/iqfiles" "$IMAGEDIR/rootfs.img" 2>/dev/null | grep -q 'Inode:'; then
		bad "rootfs.img still has the dangling /etc/iqfiles symlink into the stripped payload"
	else
		ok "no dangling /etc/iqfiles symlink in rootfs.img"
	fi
else
	skip "rootfs.img — no build present, or debugfs unavailable"
fi

echo
echo "-- $pass passed, $fail failed"
[ $fail -eq 0 ] || exit 1
