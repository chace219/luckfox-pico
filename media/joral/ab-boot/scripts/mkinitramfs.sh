#!/bin/sh
# mkinitramfs.sh — assemble the ab-boot initramfs cpio.
#
# Contents: a STATIC busybox, the STATIC misc_ab, and initramfs/init. The
# archive must be self-contained — it runs before any rootfs is mounted, so
# nothing in it may link against shared libraries.
#
# Usage:
#   scripts/mkinitramfs.sh <static-busybox> <output.cpio.gz>
#
# The busybox binary is deliberately an ARGUMENT rather than discovered: the
# buildroot-staged busybox is dynamically linked (uclibc), which will NOT work
# here. Build a static one once (buildroot BR2_STATIC_LIBS busybox-only
# config, or `make defconfig && LDFLAGS=--static make` in the busybox tree)
# and keep it with the platform build artifacts. `file <busybox>` must say
# "statically linked".
#
# Spike verification (plan, "Verification spike" (a)): pack the output into
# boot.its as the ramdisk node, flash `boot`, and confirm on serial that
# ab-boot messages appear and switch_root lands in the rootfs.
set -eu

BUSYBOX=${1:?usage: mkinitramfs.sh <static-busybox> <output.cpio.gz>}
OUT=${2:?usage: mkinitramfs.sh <static-busybox> <output.cpio.gz>}

HERE=$(dirname "$(readlink -f "$0")")
MISC_AB="$HERE/../build/misc_ab"
INIT="$HERE/../initramfs/init"

[ -f "$BUSYBOX" ] || { echo "no busybox at $BUSYBOX" >&2; exit 1; }
[ -f "$MISC_AB" ] || { echo "no misc_ab at $MISC_AB — run make first" >&2; exit 1; }
[ -f "$INIT" ]    || { echo "no init at $INIT" >&2; exit 1; }

# Refuse a dynamic busybox outright — it would boot to a silent hang.
if file "$BUSYBOX" | grep -qv "statically linked"; then
	echo "REFUSING: $BUSYBOX is not statically linked" >&2
	exit 1
fi
if file "$MISC_AB" | grep -qv "statically linked"; then
	echo "REFUSING: $MISC_AB is not statically linked (cross-build via make, not make test)" >&2
	exit 1
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

mkdir -p "$T/bin" "$T/sbin" "$T/usr/bin" "$T/usr/sbin" \
	 "$T/proc" "$T/sys" "$T/dev" "$T/mnt"

cp "$BUSYBOX" "$T/bin/busybox"
chmod 755 "$T/bin/busybox"
for a in sh mount umount echo grep cut sleep switch_root; do
	ln -s busybox "$T/bin/$a"
done
cp "$MISC_AB" "$T/usr/sbin/misc_ab"
chmod 755 "$T/usr/sbin/misc_ab"
cp "$INIT" "$T/init"
chmod 755 "$T/init"

( cd "$T" && find . | cpio -o -H newc --quiet ) | gzip -9 > "$OUT"
echo "initramfs: $OUT ($(du -h "$OUT" | cut -f1))"
