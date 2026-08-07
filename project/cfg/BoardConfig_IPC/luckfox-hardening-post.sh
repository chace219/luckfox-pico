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

echo "luckfox-hardening-post.sh: applying image hardening"
remove_stray_stunnel
