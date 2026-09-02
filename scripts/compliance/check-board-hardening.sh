#!/bin/bash
# Gate: every board profile in this SDK is hardened, or its exception is written
# down — CRA Annex I Part I #1 (secure by default) and #4 (minimise attack
# surface), compliance plan item 13.
#
# THE PROBLEM IT CLOSES. This SDK carries 16 board profiles. Two of them — the
# Pico Ultra pair Joral ships — were hardened over August 2026: no serial login,
# locked root, default-deny firewall, 118 packages removed, Wi-Fi off. The other
# 14 were untouched vendor profiles, and nothing said so. `./build.sh lunch`
# offers all 16 with the same face; a build from any of them produces a
# flashable image with the same product names on it. The difference between "the
# profile we harden" and "the profile that ships a serial root login" lived
# nowhere but in the heads of the people who did the August work.
#
# So: hardening is applied to all of them (2026-08-21), and this asserts it
# stays applied. Where a profile CANNOT take a control, the exception is named
# here with its reason — an exception in a gate is a decision; a profile nobody
# checked is an accident.
#
# WHAT IT DOES NOT CLAIM. Fifteen of the 16 profiles have no board here to boot,
# so this is a source-level check of what is configured, not evidence that any
# image built from it runs. That gap is item 13's third bullet and it is not
# closeable without the hardware.
#
# Usage: check-board-hardening.sh [--verbose]
set -u
cd "$(dirname "$0")/../.." || exit 2

# Reader for the packed rootfs — no longer always ext4. See the header of
# rootfs-image-lib.sh for why this matters to the absence check below.
. "$(dirname "$0")/rootfs-image-lib.sh"

CFGDIR=project/cfg/BoardConfig_IPC
OVERLAYDIR=$CFGDIR/overlay
HARDENING=luckfox-hardening-post.sh

# Profiles that cannot take the post-build hardening script, with the reason.
# EMMC/SPI_NAND Busybox FASTBOOT: a busybox rootfs with no buildroot package
# set, no sshd and no /etc/inittab at post-build time — their inittab is shipped
# by overlay-luckfox-fastboot, applied after the post-build hook, so the control
# that matters for them is asserted on the overlay file instead (below).
EXCEPT_POSTBUILD=(
	BoardConfig-EMMC-Busybox-RV1106_Luckfox_Pico_Ultra-IPC_FASTBOOT.mk
	BoardConfig-SPI_NAND-Busybox-RV1106_Luckfox_Pico_Pro_Max-IPC_FASTBOOT.mk
)

# Buildroot defconfigs that may be selected, and the packages none of them may
# enable: general-purpose utilities with no board function on any profile, all
# of them carrying findings in the product image's own CVE run.
DEFCONFIGS=(luckfox_pico_defconfig luckfox_pico_w_defconfig)
FORBIDDEN=(
	BR2_PACKAGE_P7ZIP BR2_PACKAGE_ZIP BR2_PACKAGE_LIBRSYNC
	BR2_PACKAGE_IPERF BR2_PACKAGE_IPERF3 BR2_PACKAGE_LRZSZ
	BR2_PACKAGE_RSYNC BR2_PACKAGE_WGET BR2_PACKAGE_SAMBA4
)

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

pass=0; fail=0
ok()   { echo "ok   — $1"; pass=$((pass+1)); }
bad()  { echo "FAIL — $1"; fail=$((fail+1)); }
note() { [ $VERBOSE -eq 1 ] && echo "       $1"; return 0; }
skip() { echo "skip — $1"; return 0; }

excepted() {
	local f=$1 e
	for e in "${EXCEPT_POSTBUILD[@]}"; do [ "$f" = "$e" ] && return 0; done
	return 1
}

mapfile -t CFGS < <(cd "$CFGDIR" && ls BoardConfig-*.mk | sort)
if [ "${#CFGS[@]}" -eq 0 ]; then
	echo "FAIL — no board configs found under $CFGDIR"; exit 1
fi
note "${#CFGS[@]} board profiles"

echo "== Post-build hardening is selected"
for f in "${CFGS[@]}"; do
	sel=$(grep -oP '^export RK_POST_BUILD_SCRIPT=\K\S+' "$CFGDIR/$f" | head -1)
	if excepted "$f"; then
		# Not a free pass: the profile still may not select something that
		# LOOKS like hardening, and its own post script must still exist.
		if [ -n "$sel" ] && [ -f "$CFGDIR/$sel" ]; then
			ok "$f — exception (busybox fastboot), keeps its board post script $sel"
		else
			bad "$f — exception profile has no working post script"
		fi
		continue
	fi
	if [ "$sel" = "$HARDENING" ]; then
		ok "$f — $HARDENING"
	else
		bad "$f — RK_POST_BUILD_SCRIPT is '${sel:-unset}', not $HARDENING: this profile would ship a serial login prompt"
	fi
done

echo
echo "== No profile enables the unSBOM'd Wi-Fi stack"
for f in "${CFGS[@]}"; do
	w=$(grep -oP '^export RK_ENABLE_WIFI=\K\S+' "$CFGDIR/$f" | head -1)
	if [ "$w" = "y" ]; then
		bad "$f — RK_ENABLE_WIFI=y ships hostapd/wpa_supplicant (2016) and prebuilt dnsmasq/iperf outside the SBOM and the CVE gate"
	fi
done
[ $fail -eq 0 ] && ok "no profile sets RK_ENABLE_WIFI=y"

wifibt=$(grep -l 'overlay-luckfox-wifibt-firmware' "$CFGDIR"/BoardConfig-*.mk 2>/dev/null || true)
if [ -n "$wifibt" ]; then
	bad "Wi-Fi/BT firmware blobs still overlaid by: $(echo "$wifibt" | xargs -n1 basename | tr '\n' ' ')"
else
	ok "no profile overlays Wi-Fi/BT firmware blobs"
fi

# RK_ENABLE_WIFI=n does NOT keep the Wi-Fi userspace out of the image, and
# assuming it did is how this gate passed for ten days while every image
# shipped the stack. project/app/wifi_app/ installs rkwifi_server, three
# wpa_supplicant builds, wpa_cli, hostapd and librkwifibt unconditionally --
# the flag governs the DRIVER, not the app layer. The compliance plan recorded
# them as "dropped from the build" on 2026-08-12; they were still in
# rootfs.img on 2026-08-22, found by reading the image rather than the claim.
#
# So assert the removal exists, and then assert the image.
if grep -q 'remove_wifi_stack' "$CFGDIR/$HARDENING" 2>/dev/null; then
	ok "$HARDENING declares remove_wifi_stack"
	if grep -qE '^remove_wifi_stack$' "$CFGDIR/$HARDENING" 2>/dev/null; then
		ok "remove_wifi_stack is actually called, not just defined"
	else
		bad "remove_wifi_stack is defined but never called — the stack would ship"
	fi
else
	bad "$HARDENING has no remove_wifi_stack — the wifi_app userspace ships on every image"
fi

WIFI_BINARIES="
	/usr/bin/rkwifi_server
	/usr/bin/wifi_start.sh
	/usr/bin/wpa_supplicant
	/usr/bin/wpa_supplicant_rtk
	/usr/bin/wpa_supplicant_nl80211_rtk
	/usr/bin/wpa_cli
	/usr/bin/wpa_cli_rtk
	/usr/bin/hostapd
	/usr/lib/librkwifibt.so
	/usr/lib/libwpa_client.so
	/etc/wpa_supplicant.conf
"
IMAGEDIR=${HARDENING_IMAGEDIR:-output/image}
# This is an ABSENCE check, so it is only worth anything while the image can
# actually be read: a reader that opens nothing reports the same empty result
# as a clean image. The rootfs is squashfs since the 2026-09-01 re-cut, which
# debugfs cannot open at all — see rootfs-image-lib.sh.
HARDENING_READER=$(rootfs_reader "$IMAGEDIR/rootfs.img" || true)
if [ -f "$IMAGEDIR/rootfs.img" ] && [ -n "$HARDENING_READER" ]; then
	shipped=""
	for wf in $WIFI_BINARIES; do
		if rootfs_has_file "$IMAGEDIR/rootfs.img" "$wf"; then
			shipped="$shipped $wf"
		fi
	done
	if [ -n "$shipped" ]; then
		bad "rootfs.img still ships the Wi-Fi userspace:$shipped — prebuilt, statically linked crypto, outside the SBOM and the CVE gate"
	else
		ok "rootfs.img ships none of the wifi_app userspace (read with $HARDENING_READER)"
	fi
else
	skip "rootfs.img Wi-Fi check — no build present, or no reader for its format (need unsquashfs for squashfs, debugfs for ext4)"
fi

echo
echo "== No shipped inittab hands out an unauthenticated console"
# Two shapes, and the second is the one that survived the August work: a getty
# asks for the shared root password, `respawn:-/bin/sh` asks for nothing at all.
# Overlay inittabs are checked here because they are applied AFTER the
# post-build hook, so the hook cannot see or fix them.
shopt -s nullglob
for tab in "$OVERLAYDIR"/*/etc/inittab; do
	rel=${tab#"$OVERLAYDIR"/}
	if grep -qE '^[^#]*getty' "$tab"; then
		bad "$rel — serial getty"
	elif grep -qE '^[^#]*respawn:-?/bin/(sh|ash|bash)' "$tab"; then
		bad "$rel — root shell on the console with no authentication"
	else
		ok "$rel — no console login"
	fi
done
shopt -u nullglob

echo
echo "== The buildroot defconfigs carry no package with a finding and no consumer"
for d in "${DEFCONFIGS[@]}"; do
	path=sysdrv/tools/board/buildroot/$d
	if [ ! -f "$path" ]; then
		bad "$path is missing"
		continue
	fi
	hits=""
	for pkg in "${FORBIDDEN[@]}"; do
		grep -q "^${pkg}=y$" "$path" && hits="$hits $pkg"
	done
	if [ -n "$hits" ]; then
		bad "$d enables:$hits"
	else
		ok "$d — none of the ${#FORBIDDEN[@]} forbidden packages"
	fi
done

# Every profile must select one of the defconfigs above; a third one would be
# unexamined by the check that just ran.
for f in "${CFGS[@]}"; do
	d=$(grep -oP '^export RK_BUILDROOT_DEFCONFIG=\K\S+' "$CFGDIR/$f" | head -1)
	[ -z "$d" ] && continue
	known=0
	for k in "${DEFCONFIGS[@]}"; do [ "$d" = "$k" ] && known=1; done
	[ $known -eq 1 ] || bad "$f selects $d, which this gate does not check"
done

echo
echo "== Buildroot profiles ship the locked-root / key-only overlay"
for f in "${CFGS[@]}"; do
	excepted "$f" && continue
	rootfs=$(grep -oP '^export LF_TARGET_ROOTFS=\K\S+' "$CFGDIR/$f" | head -1)
	[ "$rootfs" = buildroot ] || continue
	if grep -q 'overlay-luckfox-buildroot-shadow' "$CFGDIR/$f"; then
		note "$f — shadow overlay"
	else
		bad "$f — no overlay-luckfox-buildroot-shadow: root would keep a password and sshd its stock config"
	fi
done
[ $fail -eq 0 ] && ok "every buildroot profile overlays the locked root account and key-only sshd"

echo
echo "== Written exceptions (decisions, not gaps)"
cat <<'EXC'
       luckfox_pico_defconfig keeps freetype, gnutls, libmd and the python
       module set: they are the nine BSP boards' declared function (GPIO/SPI/I2C
       demos, rkipc OSD text). Revisit before any of those profiles is used for
       a product.  owner: engineering, on first product use of a BSP profile
       the two Busybox FASTBOOT profiles take no post-build hardening: their
       inittab ships from overlay-luckfox-fastboot and is asserted above
       instead.  owner: engineering
       overlay-luckfox-buildroot-tiny is referenced by no board config. Its
       console shell is disabled and its samba/bluetooth init scripts reach no
       image; deleting the directory outright is the open recommendation.
       owner: engineering
       15 of the 16 profiles have no board here: nothing below the source level
       is verified for them.  owner: engineering, needs hardware
EXC

echo
echo "-- $pass passed, $fail failed"
[ $fail -eq 0 ] || exit 1
