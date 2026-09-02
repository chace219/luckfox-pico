#!/bin/bash
# Shared reader for the packed rootfs image, sourced by the compliance gates.
#
# WHY THIS EXISTS. Until 2026-09-01 every gate read rootfs.img with `debugfs`,
# which reads ext4 and nothing else. The 2026-09-01 partition re-cut moved both
# board profiles' rootfs to **squashfs** (it packs the tree to 33 M where ext4
# needed 116 M, which is what makes a 64 M A/B slot possible), and debugfs
# returns empty on a squashfs image without failing loudly.
#
# That is worse than it sounds, and it is the reason this is a library rather
# than three copies of a one-liner. The gates ask two OPPOSITE kinds of
# question about the image:
#
#   "is this file PRESENT?"  — a dead reader answers no  -> the gate FAILS,
#                              loudly, on a good image. Annoying but visible.
#   "is this file ABSENT?"   — a dead reader answers no  -> the gate PASSES,
#                              silently, having checked nothing.
#
# The second is the dangerous one: `check-oem-payload.sh` asserts that the
# superseded /etc/init.d/S23npu and the dangling /etc/iqfiles symlink are NOT
# in the image — both of which are real defects that shipped on real units. A
# reader that cannot open the image reports exactly what a clean image reports.
# So these helpers REFUSE to answer rather than guess: callers must handle
# rootfs_reader() returning empty by SKIPPING, never by treating it as absence.
#
# Usage:
#   . "$(dirname "$0")/rootfs-image-lib.sh"
#   reader=$(rootfs_reader "$IMG")            # "" when nothing can read it
#   rootfs_has_file  "$IMG" /etc/init.d/S52npu   && ...
#   rootfs_cat_file  "$IMG" /etc/init.d/S20linkmount
#   rootfs_list_dir  "$IMG" /lib/modules

# Which tool can read this image, if any. Echoes "unsquashfs", "debugfs", or
# nothing at all. Format is probed from the image itself rather than assumed
# from the board profile: the gates run on whatever was packed last, and the
# two profiles no longer agree on the filesystem.
rootfs_reader() {
	local img=$1 desc
	[ -f "$img" ] || return 1
	desc=$(file -b "$img" 2>/dev/null)

	if printf '%s' "$desc" | grep -qi squashfs; then
		command -v unsquashfs >/dev/null 2>&1 || return 1
		# Prove the TREE lists, do not just assume the magic implies a
		# readable image. `unsquashfs -s` reads only the superblock and
		# succeeds on a truncated image whose directory table is gone — which
		# then lists as an empty tree, indistinguishable from a clean image to
		# an absence check. Listing is the operation the helpers below
		# actually perform, so it is the operation worth probing.
		unsquashfs -l "$img" 2>/dev/null | grep -q . || return 1
		echo unsquashfs
		return 0
	fi

	# erofs is the other read-only option the SDK can pack. No host tool for it
	# is assumed present; say so rather than silently reporting an empty tree.
	if printf '%s' "$desc" | grep -qi erofs; then
		command -v fsck.erofs >/dev/null 2>&1 || return 1
		echo erofs
		return 0
	fi

	# ext4 is the fallback, but it must be CONFIRMED rather than assumed. A
	# file `file` cannot identify — a truncated image, a stray blob, a format
	# nothing here reads — used to land in this branch and be reported as a
	# working debugfs reader. Every absence check would then pass against an
	# image that had never been opened.
	if printf '%s' "$desc" | grep -qiE 'ext[234] filesystem'; then
		command -v debugfs >/dev/null 2>&1 || return 1
		debugfs -R "stat /" "$img" 2>/dev/null | grep -q 'Inode:' || return 1
		echo debugfs
		return 0
	fi

	return 1
}

# True if PATH exists in the image. Callers MUST check rootfs_reader first —
# with no reader this returns false, which is indistinguishable from absence
# and would quietly satisfy an "is not present" assertion.
rootfs_has_file() {
	local img=$1 path=$2
	case "$(rootfs_reader "$img")" in
	unsquashfs)
		unsquashfs -l "$img" 2>/dev/null | grep -qxF "squashfs-root$path"
		;;
	debugfs)
		debugfs -R "stat $path" "$img" 2>/dev/null | grep -q 'Inode:'
		;;
	*)
		return 1
		;;
	esac
}

# Contents of PATH from the image, on stdout. Empty when unreadable.
rootfs_cat_file() {
	local img=$1 path=$2 tmp rc
	case "$(rootfs_reader "$img")" in
	unsquashfs)
		# NOT `unsquashfs -cat`. That option arrived in squashfs-tools 4.4,
		# and `./build.sh` puts the SDK's OWN unsquashfs — 4.3, from 2014, in
		# output/out/sysdrv_out/pc — ahead of the host's on PATH. Under
		# build.sh the 4.3 binary printed its usage banner and returned
		# nothing, so the check reported "could not read it" and SKIPPED,
		# while the same gate run directly from a shell passed. A check that
		# quietly disappears in the invocation everyone actually uses is
		# worse than one that fails.
		#
		# Extracting one file to a temp directory works on both versions.
		tmp=$(mktemp -d) || return 1
		unsquashfs -n -f -d "$tmp" "$img" "$path" >/dev/null 2>&1
		rc=0
		if [ -f "$tmp$path" ]; then cat "$tmp$path"; else rc=1; fi
		rm -rf "$tmp"
		return $rc
		;;
	debugfs)
		debugfs -R "cat $path" "$img" 2>/dev/null
		;;
	esac
}

# Bare entry names directly under DIR, one per line.
rootfs_list_dir() {
	local img=$1 dir=$2
	case "$(rootfs_reader "$img")" in
	unsquashfs)
		unsquashfs -l "$img" 2>/dev/null |
			sed -n "s|^squashfs-root${dir}/\([^/]*\)$|\1|p"
		;;
	debugfs)
		debugfs -R "ls -p $dir" "$img" 2>/dev/null |
			awk -F/ '/^\//{ if ($6 != "" && $6 != "." && $6 != "..") print $6 }'
		;;
	esac
}
