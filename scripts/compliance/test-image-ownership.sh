#!/bin/bash
# Guard the root-owned-inode pass in the SHARED ext4 packer
# (sysdrv/tools/pc/e2fsprogs/mkfs_ext4.sh) — CRA Annex I Part I #3 and #5.
#
# Why this is a test and not a comment: the defect it guards has now been
# reintroduced twice by mechanisms that each LOOKED like they were working.
#
#   1. The originally planned fix wrapped chown+mkfs.ext4 in fakeroot. The
#      SDK's mkfs.ext4 is statically linked and fakeroot is LD_PRELOAD, so it
#      would have passed its own `command -v fakeroot` check and shipped the
#      identical defect (2026-08-15).
#   2. The shipped fix then verified itself with a stat list derived by sed
#      from the very list it had just applied, so it could only ever catch
#      debugfs refusing a line — never a tree the list failed to describe. A
#      path containing a NEWLINE, which the code's own comment claimed was
#      refused and which nothing actually checked, produced: packer exit 0,
#      verify pass reporting zero bad inodes, and the file still 1000:1000 in
#      the image (found 2026-08-19, working item 13).
#
# Both were checks that could not fail. So this file asserts the packer FAILS
# when it should, not merely that it succeeds when nothing is wrong.
#
# Runs on a clean checkout: it builds its own throwaway staging trees and uses
# the tracked SDK e2fsprogs binaries. No board build required.
#
# Usage: test-image-ownership.sh
set -u
cd "$(dirname "$0")/../.." || exit 2

PACKER=sysdrv/tools/pc/e2fsprogs/mkfs_ext4.sh
E2FSDIR=sysdrv/tools/pc/e2fsprogs
SIZE=$((32 * 1024 * 1024))

pass=0; fail=0
ok()  { echo "ok   — $1"; pass=$((pass+1)); }
bad() { echo "FAIL — $1"; fail=$((fail+1)); }

[ -f "$PACKER" ] || { echo "$PACKER missing"; exit 2; }
command -v debugfs >/dev/null || { echo "debugfs (e2fsprogs) required"; exit 2; }

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# A doctored copy of the packer runs from $TMP, and the packer resolves its
# e2fsprogs through its own directory — so they have to travel with it.
cp -a "$E2FSDIR"/mkfs.ext4 "$E2FSDIR"/resize2fs "$E2FSDIR"/e2fsck "$E2FSDIR"/tune2fs "$TMP/"

# mode_of <image> <path> -> "uid:gid" as read back OUT OF THE IMAGE
owner_in_image() {
	debugfs -R "stat $2" "$1" 2>/dev/null |
		awk '/^User:/ {print $2 ":" $4; exit}'
}

echo "== An ordinary tree packs root-owned"
mkdir -p "$TMP/plain/etc/ssh"
echo hash    > "$TMP/plain/etc/shadow"
echo key     > "$TMP/plain/etc/ssh/authorized_keys"
if "$PACKER" "$TMP/plain" "$TMP/plain.img" "$SIZE" >"$TMP/plain.log" 2>&1; then
	ok "packer succeeded on a normal tree"
	badinodes=0
	for p in / /etc /etc/shadow /etc/ssh /etc/ssh/authorized_keys; do
		o=$(owner_in_image "$TMP/plain.img" "$p")
		[ "$o" = "0:0" ] || { bad "$p is $o in the packed image, not 0:0"; badinodes=1; }
	done
	[ $badinodes -eq 0 ] && ok "/, /etc, /etc/shadow and the SSH key path are all 0:0 in the image"
	grep -q 'walked .* all uid/gid 0' "$TMP/plain.log" &&
		ok "packer verified the image by walking it" ||
		bad "packer did not report an ownership walk (see $TMP/plain.log)"
else
	bad "packer failed on a normal tree (see $TMP/plain.log)"
fi

echo "== A path debugfs cannot address is REFUSED, not half-applied"
# debugfs's command file quotes paths, so a name containing a double quote or a
# newline cannot be expressed. Such an inode would silently keep build-host
# ownership.
for name in 'sha"dow' "$(printf 'shadow\nevil')"; do
	rm -rf "$TMP/hostile"; mkdir -p "$TMP/hostile/etc"
	echo hash > "$TMP/hostile/etc/$name"
	label=$(printf '%q' "$name")
	if "$PACKER" "$TMP/hostile" "$TMP/hostile.img" "$SIZE" >"$TMP/hostile.log" 2>&1; then
		bad "packer accepted a tree containing /etc/$label"
	else
		ok "packer refused a tree containing /etc/$label"
	fi
done

echo "== With the guard bypassed, the walk still catches it"
# The guard above is the legible half. The load-bearing half is that the
# verification reads the IMAGE independently of the list that was applied to
# it, so it catches an unowned inode the list never named. Simulated by
# disabling the guard in a copy.
# The guard itself spans two source lines, because the pattern it matches
# contains a literal newline — so it is removed as a block, from its `if` to
# the matching `fi`, rather than by line-matching.
awk '
	/^\tif find "\$src" -mindepth 1/ { skip = 1; print "\tif false; then"; print "\t\t:"; next }
	skip && /^\tfi$/                  { skip = 0; print; next }
	skip                              { next }
	                                  { print }
' "$PACKER" > "$TMP/noguard.sh"
if ! bash -n "$TMP/noguard.sh" 2>/dev/null; then
	bad "could not build a guard-bypassed copy of the packer (its shape changed — update this test)"
else
	rm -rf "$TMP/hostile"; mkdir -p "$TMP/hostile/etc"
	echo hash > "$TMP/hostile/etc/$(printf 'shadow\nevil')"
	if bash "$TMP/noguard.sh" "$TMP/hostile" "$TMP/nl.img" "$SIZE" >"$TMP/nl.log" 2>&1; then
		bad "guard bypassed: packer shipped an image with a non-root inode"
	else
		grep -q 'not 0:0' "$TMP/nl.log" &&
			ok "guard bypassed: the independent walk found the unowned inode" ||
			bad "guard bypassed: packer failed, but not because of the ownership walk"
	fi
fi

echo "== A root uid with a non-root gid is caught too"
# The superseded check grepped "User:" only, so 0:1000 passed it.
sed 's|^\tdebugfs -w -f "$own_cmds" "$dst" >/dev/null 2>&1|\tgrep -v " gid 0$" "$own_cmds" > "$own_cmds.u"; debugfs -w -f "$own_cmds.u" "$dst" >/dev/null 2>\&1; rm -f "$own_cmds.u"|' \
	"$PACKER" > "$TMP/gidonly.sh"
if ! grep -q 'own_cmds.u' "$TMP/gidonly.sh"; then
	bad "could not build a gid-dropping copy of the packer (its shape changed — update this test)"
elif bash "$TMP/gidonly.sh" "$TMP/plain" "$TMP/gid.img" "$SIZE" >"$TMP/gid.log" 2>&1; then
	bad "an image whose gids stayed 1000 was accepted"
else
	grep -q '0:[1-9]' "$TMP/gid.log" &&
		ok "a non-root gid under a root uid is rejected" ||
		bad "packer failed, but not because of the group ownership"
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
