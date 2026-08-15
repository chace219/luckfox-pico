#!/bin/bash

err_handler() {
	ret=$?
	[ "$ret" -eq 0 ] && return

	msg_error "Running ${FUNCNAME[1]} failed!"
	msg_error "exit code $ret from line ${BASH_LINENO[0]}:"
	msg_info "    $BASH_COMMAND"
	exit $ret
}

trap 'err_handler' ERR
# source files
src=$1
# generate image
dst=$2

if [ -z "$3" -o -z "$dst" -o ! -d "$src" ]; then
	echo "command format: $(basename $0) <source> <dest image> <partition size>"
	exit 0
fi

# the size of generate image, get info from parameter.txt
# eg. 0x00040000@0x00016000(rootfs)
# calculate size fo rootfs partition: 0x00040000 * 512 = 128*0x100000 (Bytes)
dst_size="$(( $3 / 1024 / 1024 ))M"

cwd=$(dirname $(readlink -f $0))
export PATH=$cwd:$PATH

rm -f $dst

bin_dir=./
if [ -f $cwd/bin/mkfs.ext4 ];then
	bin_dir=bin
fi

mkdir -p $(dirname $dst)

echo mkfs.ext4 -d $src -r 1 -N 0 -m 5 -L \"\" -O ^64bit,^huge_file $dst \"$dst_size\"
mkfs.ext4 -d $src -r 1 -N 0 -m 5 -L "" -O ^64bit,^huge_file $dst "$dst_size"
if [ $? != 0 ]; then
	echo "*** Maybe you need to increase the filesystem size "
	exit 1
fi
# ── Root-owned inodes (CRA Annex I Part I §3 and §5) ────────────────────────
#
# `mkfs.ext4 -d` copies the staging tree PRESERVING build-host ownership, and
# the build runs unprivileged — so without this pass every inode in the image
# is owned by the build user (uid 1000 on a normal developer host), including
# /, /etc, /etc/shadow and /etc/ssh. Two consequences:
#
#   1. sshd cannot use StrictModes at its default, because it requires the
#      authorized-keys file and every directory on its path to be owned by root
#      or the logging-in user. Nothing in the image qualifies.
#   2. It is a latent privilege escalation. A service account added with an
#      automatic UID lands at 1000 and would then own the ENTIRE root
#      filesystem — /etc/shadow, every init script, the SSH key, the OPC UA
#      private key. It is inert today only because no uid-1000 account exists
#      in /etc/passwd, and CRA hardening actively pushes toward running daemons
#      unprivileged.
#
# This is deliberately NOT done with fakeroot. The obvious fix — wrapping
# `chown -R 0:0` and mkfs.ext4 in a single fakeroot session — silently does
# NOTHING here: the mkfs.ext4 this script puts on PATH is the SDK's own
# STATICALLY LINKED binary, and fakeroot works by LD_PRELOAD. It would pass a
# `command -v fakeroot` check and emit an image carrying the identical defect.
# Measured both ways: static binary under fakeroot -> uid 1000; the host's
# dynamic binary -> uid 0. Switching to the host's mkfs.ext4 was rejected
# separately, because this script pins the SDK's e2fsprogs to control the
# feature set and a newer host mke2fs enables on-disk features the target
# kernel may refuse to mount.
#
# So ownership is corrected in the PACKED IMAGE instead, using debugfs — which
# is already a required build tool (build.sh reads the release identity back
# out of the rootfs the same way). The path list comes from $src, which is by
# construction the tree that was just packed, so it cannot drift from the
# image's contents the way a separately-maintained list would.
#
# Set MKFS_EXT4_KEEP_BUILD_OWNERSHIP=1 to skip, for a caller that genuinely
# needs build-host ownership preserved.
if [ "${MKFS_EXT4_KEEP_BUILD_OWNERSHIP:-0}" != "1" ]; then
	if ! command -v debugfs >/dev/null 2>&1; then
		echo "*** debugfs (e2fsprogs) is required to give $dst root-owned inodes."
		echo "*** Without it the image would ship with /etc/shadow and /etc/ssh"
		echo "*** owned by the build user. Install e2fsprogs, or set"
		echo "*** MKFS_EXT4_KEEP_BUILD_OWNERSHIP=1 to accept that deliberately."
		exit 1
	fi

	own_cmds=$(mktemp)
	# A path carrying a double quote or a newline would break the command file
	# and silently leave those inodes unowned. Refuse rather than half-apply.
	if find "$src" -mindepth 1 -name '*"*' -print -quit | grep -q .; then
		echo "*** $src contains a path with a double quote; cannot set ownership safely"
		rm -f "$own_cmds"
		exit 1
	fi
	{
		printf 'sif / uid 0\nsif / gid 0\n'
		find "$src" -mindepth 1 -printf '%P\n' | while IFS= read -r p; do
			printf 'sif "/%s" uid 0\nsif "/%s" gid 0\n' "$p" "$p"
		done
	} > "$own_cmds"
	echo "debugfs: setting $(( $(wc -l < "$own_cmds") / 2 )) inodes to uid/gid 0 in $dst"
	debugfs -w -f "$own_cmds" "$dst" >/dev/null 2>&1

	# Verify against the IMAGE, not against the tooling. This whole pass exists
	# because the obvious approach fails silently, so a build that merely ran
	# the right command proves nothing — read the ownership back out.
	sed -e 's/^sif /stat /' -e 's/ uid 0$//' -e '/ gid 0$/d' "$own_cmds" > "$own_cmds.verify"
	# `grep -c` exits 1 when the count is zero — which is the SUCCESS case here.
	# Left bare it trips this script's ERR trap and aborts the build after the
	# ownership pass but before resize2fs, silently shipping an unshrunk image.
	bad=$(debugfs -f "$own_cmds.verify" "$dst" 2>/dev/null | grep -c '^User: *[1-9]' || true)
	rm -f "$own_cmds" "$own_cmds.verify"
	if [ "${bad:-1}" -ne 0 ]; then
		echo "*** $bad inode(s) in $dst are still owned by a non-root uid"
		exit 1
	fi
fi

echo "resize2fs -M $dst"
resize2fs -M $dst
echo "e2fsck -fy  $dst"
e2fsck -fy  $dst
echo "tune2fs -m 5  $dst"
tune2fs -m 5  $dst
echo "resize2fs -M $dst"
resize2fs -M $dst
