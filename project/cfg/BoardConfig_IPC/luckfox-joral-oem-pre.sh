#!/bin/bash
#
# Pre-OEM-package hook for the Joral product profiles (Pico Ultra, single-slot
# and A/B).  Selected by RK_PRE_BUILD_OEM_SCRIPT; build.sh runs it from
# __RUN_PRE_BUILD_OEM_SCRIPT, after __PACKAGE_OEM has filled the OEM staging
# directory and before build_mkimg packs it into oem.img.
#
# WHAT IT DOES: empties the oem payload, after rescuing the two kernel modules
# that are genuinely used, into the rootfs.
#
# WHY.  __PACKAGE_RESOURCES fills the oem staging directory from the BSP's
# media/app output with no notion of what the product runs: 198 files, 21 MB,
# measured on the 2026.08.12 build.  It is the whole Rockchip IPC demo suite —
# rkipc and ~60 sample_*/rk_*_test binaries, librockit/librkaiq and the rest of
# the camera pipeline, the AIC8800 Wi-Fi driver and its firmware blob, camera
# sensor and ISP modules, an OSD font, a speaker test wav — plus a SECOND,
# divergent copy of the SATISense console (a different assets/index-* bundle
# and differing cgi-bin/*.sh from the one the rootfs serves).
#
# Not one line of it is reachable on this product:
#   - the overlay's S21appinit replaces the BSP's, so RkLunch.sh — which is what
#     runs rkipc and insmod_ko.sh — never executes;
#   - nothing else insmods anything from /oem/usr/ko (grep the packed rootfs);
#   - the daemon's library path stopped naming /oem in release 2026.08.5 and
#     login shells stopped in 2026.08.6 (RkEnv.sh removed, see
#     luckfox-hardening-post.sh);
#   - the console copy on oem is served by nothing: no httpd roots there.
#
# So it is 21 MB of unreferenced root-owned executables on a shipped device,
# outside the SBOM (which describes the rootfs) and outside `./build.sh cve`.
# That is Annex I #4 in the same shape as the 118 buildroot packages removed on
# 2026-08-10 and the BSP daemons removed on 2026-08-08 — inherited defaults
# rather than product requirements — one partition across.
#
# WHAT IS KEPT, and why it moves rather than stays:
#   rknpu.ko  the NPU driver.  The SATISense daemon links librknnmrt and
#             core/ai/aiworker.c runs the MVAD autoencoder's INT8 sibling
#             through rknn_init() when a .rknn model is present.  The module is
#             built (CONFIG_ROCKCHIP_RKNPU=m) but nothing has ever loaded it, so
#             that path could not work on any unit ever shipped.  It is loaded
#             now by the overlay's S52npu.
#   pwm_bl.ko the RGB backlight, insmod'd by the rgb overlay's S25backlight.
#             Kept to preserve existing behaviour exactly — this change is about
#             where the payload lives, not about dropping a display feature.
#
# Both move to /lib/modules/<vermagic>/ IN THE ROOTFS rather than staying on
# oem, for the reason item 14 of the compliance plan exists: oem is single-copy,
# absent from the .swu payload, and the A/B updater can never write it.  A file
# the updater cannot replace is a file no security fix can reach.  The version
# directory is read out of the module's own vermagic, so the loader can ask for
# $(uname -r) and a module that does not match the running kernel is simply not
# found — a silent miss the log names, rather than an insmod that fails deep in
# the boot with a version-magic error.
#
# FIELDED UNITS: this only governs what a FLASH writes.  oem is not in the .swu,
# so a unit already in the field keeps whatever its factory flash put there —
# which is why the overlay also ships S22oemclean, the runtime half of this
# change.  The two belong together: without the init script this is a control on
# new units only, and item 14's residual ("no update can fix it, only a
# reflash") would still stand.
#
# Keep in step with scripts/compliance/check-oem-payload.sh, which asserts the
# packed image against this script's intent, and with the two init scripts.

set -e

if [ -z "$RK_PROJECT_PACKAGE_OEM_DIR" ] || [ ! -d "$RK_PROJECT_PACKAGE_OEM_DIR" ]; then
	echo "luckfox-joral-oem-pre.sh: RK_PROJECT_PACKAGE_OEM_DIR unset or missing" >&2
	exit 1
fi
if [ -z "$RK_PROJECT_PACKAGE_ROOTFS_DIR" ] || [ ! -d "$RK_PROJECT_PACKAGE_ROOTFS_DIR" ]; then
	echo "luckfox-joral-oem-pre.sh: RK_PROJECT_PACKAGE_ROOTFS_DIR unset or missing" >&2
	exit 1
fi

OEM_DIR="$RK_PROJECT_PACKAGE_OEM_DIR"
ROOTFS_DIR="$RK_PROJECT_PACKAGE_ROOTFS_DIR"

# The modules to rescue, in the order they are reported.
KEEP_MODULES="rknpu.ko pwm_bl.ko"

function module_vermagic() {
	# vermagic is a NUL-terminated string in .modinfo; strings(1) is not
	# guaranteed on a build host, so read it with tr rather than depending on
	# binutils.
	tr '\0' '\n' <"$1" | sed -n 's/^vermagic=\([^ ]*\).*/\1/p' | head -n1
}

function rescue_modules() {
	local ko src rel dst kept=0

	for ko in $KEEP_MODULES; do
		src="$OEM_DIR/usr/ko/$ko"
		if [ ! -f "$src" ]; then
			# Not every board profile builds every module. Missing is not
			# an error here — S52npu and S25backlight both tolerate the
			# module being absent — but it must be visible in the log,
			# because a silently-missing rknpu.ko is indistinguishable
			# from one that was rescued.
			echo "luckfox-joral-oem-pre.sh: $ko not in the oem payload, nothing to rescue"
			continue
		fi

		rel=$(module_vermagic "$src")
		if [ -z "$rel" ]; then
			echo "luckfox-joral-oem-pre.sh: no vermagic in $src — refusing to guess a module path" >&2
			exit 1
		fi

		dst="$ROOTFS_DIR/lib/modules/$rel"
		mkdir -p "$dst"
		cp -f "$src" "$dst/$ko"
		chmod 0644 "$dst/$ko"
		echo "luckfox-joral-oem-pre.sh: rescued $ko -> /lib/modules/$rel/$ko"
		kept=$((kept + 1))
	done

	echo "luckfox-joral-oem-pre.sh: rescued $kept module(s) into the rootfs"
}

function strip_oem_payload() {
	local files bytes

	files=$(find "$OEM_DIR" -type f | wc -l)
	bytes=$(du -sh "$OEM_DIR" 2>/dev/null | cut -f1)
	echo "luckfox-joral-oem-pre.sh: dropping the BSP oem payload ($files files, $bytes)"

	# rm the CONTENTS, not the directory: build_mkimg is called with this path
	# and __PACKAGE_OEM has already created it.
	find "$OEM_DIR" -mindepth 1 -delete

	# __PACKAGE_OEM symlinks /etc/iqfiles -> ../oem/usr/share/iqfiles into the
	# rootfs when it staged ISP tuning files. With the payload gone that is a
	# dangling symlink, and a dangling symlink in /etc is exactly the kind of
	# thing that gets read as "this image expects camera tuning that failed to
	# install".
	rm -f "$ROOTFS_DIR/etc/iqfiles"
}

function assert_empty() {
	local left
	left=$(find "$OEM_DIR" -mindepth 1 | wc -l)
	if [ "$left" -ne 0 ]; then
		echo "luckfox-joral-oem-pre.sh: FAILED to empty $OEM_DIR ($left entries remain)" >&2
		find "$OEM_DIR" -mindepth 1 >&2
		exit 1
	fi
	echo "luckfox-joral-oem-pre.sh: oem payload is empty"
}

echo "luckfox-joral-oem-pre.sh: stripping the oem partition payload"
rescue_modules
strip_oem_payload
assert_empty
