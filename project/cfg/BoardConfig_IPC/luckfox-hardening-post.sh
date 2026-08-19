#!/bin/bash
#
# Post-build hardening for the Joral edge images.
#
# Invoked by build.sh __RUN_POST_BUILD_SCRIPT, which runs against
# $RK_PROJECT_PACKAGE_ROOTFS_DIR before the rootfs image is packed - so
# anything removed here never reaches the device.
#
# This is the home for "buildroot/BSP ships it, we do not want it" deletions
# that cannot be expressed as a defconfig or overlay change.

# Guard: never operate on / if the build did not export the rootfs path.
if [ -z "$RK_PROJECT_PACKAGE_ROOTFS_DIR" ] || [ ! -d "$RK_PROJECT_PACKAGE_ROOTFS_DIR" ]; then
	echo "luckfox-hardening-post.sh: RK_PROJECT_PACKAGE_ROOTFS_DIR unset or missing, skipping"
	exit 0
fi

function remove_stray_stunnel() {
	# The buildroot stunnel package installs an init script and the upstream
	# Windows SAMPLE config (stunnel.mk: STUNNEL_INSTALL_CONF /
	# STUNNEL_INSTALL_INIT_SYSV). That sample opens client tunnels on
	# 127.0.0.1:110/143/25 to pop/imap/smtp.gmail.com and verifies against a
	# ca-certs.pem that does not exist in this rootfs.
	#
	# Nothing on this product uses it: S60intelligence-edge generates its own
	# /var/run/intelligence-edge/stunnel-web.conf and starts stunnel under its
	# own pidfile when web.tls is enabled (ADR-129).
	#
	# The stunnel BINARY is a genuine dependency and is deliberately kept -
	# only the stray init script and sample config are removed. Leaving them
	# makes a running unit look like console TLS is configured when web.tls
	# is false and the console is plain HTTP.
	rm -fv "$RK_PROJECT_PACKAGE_ROOTFS_DIR/etc/init.d/S50stunnel"
	rm -rfv "$RK_PROJECT_PACKAGE_ROOTFS_DIR/etc/stunnel"
}

function remove_oem_loader_path() {
	# /etc/profile.d/RkEnv.sh is Rockchip BSP boilerplate for the IPC camera
	# app (rkipc), which this image deliberately does not run (see the board
	# overlay's S21appinit). It sets HOME=/oem, appends /oem/{,usr/}{bin,sbin}
	# to PATH, and — the part that matters — PREPENDS /oem/usr/lib:/oem/lib to
	# LD_LIBRARY_PATH.
	#
	# /oem is the one partition the A/B updater never writes: single-copy, no
	# standby, absent from the .swu payload. It therefore still carries
	# build-host ownership on every unit flashed before 2026-08-15 —
	# /oem/usr measured drwxrwxr-x 1000 1000 on a bench unit — and no update
	# can ever re-own it. Only a reflash can.
	#
	# So this file put a uid-1000-writable directory AHEAD of /usr/lib on the
	# library search path of every interactive root login. The daemon half of
	# the same exposure was fixed in 2026.08.5 by shipping librknnmrt.so in the
	# rootfs and dropping the export from S60intelligence-edge; profile.d is
	# sourced only by login shells, so that fix did not reach this one, and an
	# `ldd` on the daemon looked clean while an admin's own shell did not.
	# See the compliance plan, item 14.
	#
	# Its only consumer in this image is the BSP's S60micinit, which is
	# already a permanent no-op: it guards everything behind
	# `command -v amixer`, and amixer is in neither the rootfs nor oem. The
	# source line there is guarded with `[ -f ... ] &&`, so removing the file
	# is inert for it.
	rm -fv "$RK_PROJECT_PACKAGE_ROOTFS_DIR/etc/profile.d/RkEnv.sh"
}

function remove_serial_getty() {
	# Buildroot's skeleton inittab puts a respawning login prompt on the
	# serial console:
	#
	#     console::respawn:/sbin/getty -L  console 0 vt100 # GENERIC_SERIAL
	#
	# Product decision 2026-08-19: serial console access is NOT provided to
	# customers or to developers on production images, so that prompt has no
	# supported use and is pure attack surface — a login served on exposed
	# board pads to anyone holding the hardware, guarded by one password
	# shared across the whole fleet.
	#
	# Removing it is what makes locking the root account free. SSH is already
	# PermitRootLogin prohibit-password, so the password had no network use;
	# with no getty it has no local use either, and the overlay's /etc/shadow
	# ships root as `*` in the same change. A getty left behind a locked
	# account, or a locked account behind a live getty, is worse than either
	# on its own — the two belong together.
	#
	# This removes the LOGIN prompt, not console output: the kernel still
	# prints its boot log to the same device via the console= cmdline
	# argument, so a bench operator keeps everything except the ability to
	# authenticate.
	#
	# Fails the build rather than shipping a unit that still serves it — the
	# same posture as the image-ownership check. A silently-skipped hardening
	# step is indistinguishable from one that ran.
	local inittab="$RK_PROJECT_PACKAGE_ROOTFS_DIR/etc/inittab"
	if [ ! -f "$inittab" ]; then
		echo "luckfox-hardening-post.sh: /etc/inittab missing, cannot remove getty" >&2
		exit 1
	fi
	sed -i '/getty/d' "$inittab"
	if grep -q getty "$inittab"; then
		echo "luckfox-hardening-post.sh: FAILED to remove the serial getty from $inittab" >&2
		exit 1
	fi
	echo "removed serial getty from /etc/inittab"
}

echo "luckfox-hardening-post.sh: applying image hardening"
remove_stray_stunnel
remove_oem_loader_path
remove_serial_getty
