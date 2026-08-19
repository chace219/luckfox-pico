#!/bin/bash

# source files
src=$1
# generate image
dst=$2
# erofs compression
EROFS_COMP=$3

err_handler() {
	ret=$?
	[ "$ret" -eq 0 ] && return

	msg_error "Running ${FUNCNAME[1]} failed!"
	msg_error "exit code $ret from line ${BASH_LINENO[0]}:"
	msg_info "    $BASH_COMMAND"
	exit $ret
}

trap 'err_handler' ERR
if [ -z "$2" -o ! -d "$src" ]; then
	echo "command format: $(basename $0) <source> <dest image> <compression>"
	echo "        <compression>   lz4|lz4hc (default lz4hc)"
	exit 0
fi

case $EROFS_COMP in
lz4|lz4hc)
	erofs_compression_args=$EROFS_COMP
	;;
*)
	erofs_compression_args=lz4hc
	;;
esac

cwd=$(dirname $(readlink -f $0))
export PATH=$cwd:$PATH

MKEROFS_TOOL=mkfs.erofs

rm -f $dst
mkdir -p $(dirname $dst)

# ── Root-owned inodes (CRA Annex I Part I #3 and #5) ───────────────────────
#
# mkfs.erofs, like every -d/-r style packer, copies the staging tree PRESERVING
# build-host ownership — and the build runs unprivileged, so without this every
# inode lands uid 1000, including /etc/shadow and /etc/ssh. The ext4 path was
# fixed 2026-08-15 with a debugfs pass over the packed image; this path was
# missed because no board we ship uses erofs.
#
# Measured 2026-08-19 on the real staging tree before this flag: dump.erofs
# reported /etc/shadow as "Uid: 1000  Gid: 1000".
#
# Unlike ext4 this needs no post-pass: mkfs.erofs takes --all-root itself. The
# one thing worth knowing is that the SPI_NAND caller (mkfs_ubi.sh) runs this
# tool inside a `fakeroot` session that has just done `chown -h -R 0:0`, and
# that does NOTHING — fakeroot is LD_PRELOAD and mkfs.erofs is statically
# linked, exactly as with the SDK's mkfs.ext4. So the flag is the fix, not the
# belt-and-braces; do not remove it on the theory that fakeroot has it covered.
mkerofs_cmd="$MKEROFS_TOOL $dst $src -Enoinline_data --all-root"
echo $mkerofs_cmd
eval $mkerofs_cmd
