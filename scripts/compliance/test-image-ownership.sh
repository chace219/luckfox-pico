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

# ── The other two packers ───────────────────────────────────────────────────
# ext4 is the product's filesystem and everything above is about it. These are
# the SPI_NAND profiles' packers, and until 2026-08-21 they were the half of
# the SDK the 08-15 ownership fix never reached: mkfs_ubi.sh wrapped a chown
# and the packer in one fakeroot session, and mkfs.ubifs/mkfs.erofs/ubinize are
# statically linked, so the shim they were supposed to obey was never loaded.
# The mechanism was present, plausible, and worked for exactly one filesystem
# out of three — which is why it survived review for years.
UBIPACKER=sysdrv/tools/pc/mtd-utils/mkfs_ubi.sh
UBICHECK=sysdrv/tools/pc/mtd-utils/check-ubifs-ownership.py

echo "== ubifs packs root-owned, root inode included"
if [ ! -x "$UBIPACKER" ] || [ ! -x "$UBICHECK" ]; then
	bad "$UBIPACKER or $UBICHECK missing"
else
	mkdir -p "$TMP/ubi/src/etc" "$TMP/ubi/out"
	echo hash > "$TMP/ubi/src/etc/shadow"
	if RK_DEBUG=1 "$UBIPACKER" "$TMP/ubi/src" "$TMP/ubi/out" $((128 * 1024 * 1024)) \
		rootfs ubifs lzo >"$TMP/ubi/log" 2>&1 && [ -f "$TMP/ubi/out/rootfs.img" ]; then
		if "$UBICHECK" "$TMP/ubi/out/rootfs.img" --quiet >/dev/null 2>&1; then
			ok "every inode in the packed ubi image is uid 0 / gid 0"
		else
			bad "the packed ubi image still carries build-user ownership: $("$UBICHECK" "$TMP/ubi/out/rootfs.img" | tail -2 | tr '\n' ' ')"
		fi
	else
		bad "the ubi packer failed: $(tail -3 "$TMP/ubi/log" | tr '\n' ' ')"
	fi

	# The fix is a user namespace, so the test that matters is what happens
	# WITHOUT one — on a host where unprivileged userns is disabled, the packer
	# must fail rather than quietly emit a 1000:1000 image. Simulated by making
	# `unshare` unavailable, which is the same thing from the script's side.
	mkdir -p "$TMP/ubi/stub" "$TMP/ubi/out2"
	printf '#!/bin/sh\nexit 1\n' > "$TMP/ubi/stub/unshare"
	chmod +x "$TMP/ubi/stub/unshare"
	if PATH="$TMP/ubi/stub:$PATH" RK_DEBUG=1 "$UBIPACKER" "$TMP/ubi/src" "$TMP/ubi/out2" \
		$((128 * 1024 * 1024)) rootfs ubifs lzo >"$TMP/ubi/log2" 2>&1; then
		bad "with no user namespace the packer SUCCEEDED — it fell back to fakeroot and shipped build-user ownership"
	elif grep -q 'the filesystem root' "$TMP/ubi/log2"; then
		ok "with no user namespace the build fails, naming the root inode"
	else
		bad "the packer failed without a namespace, but not on the ownership check"
	fi
fi

echo "== erofs-on-ubi carries --all-root"
# mkfs_erofs.sh got this on 2026-08-19; this second, ubi-wrapped invocation of
# the same tool did not, and SPI_NAND profiles use THIS one.
if grep -q 'MKEROFS_TOOL .*--all-root' "$UBIPACKER"; then
	ok "the erofs invocation inside the ubi packer passes --all-root"
else
	bad "the erofs invocation inside the ubi packer has no --all-root — a static packer cannot see the fakeroot chown"
fi

# ── The privop dispatchers must be setuid root ──────────────────────────────
# The consoles run as www-data and reach root ONLY through these two binaries.
# Without the setuid bit every privileged verb fails with "cannot become root
# (not installed setuid?)", so the console cannot stage a .swu, read the A/B
# misc record, apply config or reboot -- and on the bench it presented as a
# firmware upload dying mid-body with "network error", which points nowhere
# near a file mode. Bench, Max, 2026-09-10.
#
# Each product Makefile installs 4755 and the mode survives into
# output/out/media_out/root/, but the packing pass clears it, so build.sh
# re-asserts it in __HARDEN_SECRET_FILE_MODES immediately before the image is
# built. This checks BOTH halves: that the re-assertion is still in build.sh,
# and -- when a staged tree is present -- that it actually took effect.
echo "== the console privop dispatchers are setuid root"
if grep -q 'chmod 4755 "\$RK_PROJECT_PACKAGE_ROOTFS_DIR/\$f"' project/build.sh; then
	ok "build.sh re-asserts setuid on the privop dispatchers"
else
	bad "build.sh no longer re-asserts setuid on the privop dispatchers — the console would lose every privileged verb"
fi

# The staged tree is NOT the place to check this, and that mistake is worth
# recording: the packer's own `chown -h -R 0:0` runs last and clears the bit
# there every time, so output/out/rootfs_uclibc_rv1106 legitimately shows 755
# after a successful build. What matters is the mode INSIDE the image, which no
# host tool in this SDK can read (see ubifs-read.py's header). So assert the
# mechanism instead: the restore must be emitted into the fakeroot script,
# after the chown, for BOTH fakeroot paths.
if grep -q '__emit_setuid_restore' "$UBIPACKER"; then
	ok "the ubi packer re-asserts setuid after its chown"
	_n=$(grep -c '^\s*__emit_setuid_restore\s*$' "$UBIPACKER")
	if [ "$_n" -ge 2 ]; then
		ok "both fakeroot paths (userns and fakeroot) restore it"
	else
		bad "only $_n of the 2 fakeroot paths restore setuid — one packer route still ships a 755 dispatcher"
	fi
	if grep -q 'chmod 4755 \$ROOTFS_SRC_DIR/\$p' "$UBIPACKER"; then
		ok "the emitted line chmods 4755 inside the fakeroot session"
	else
		bad "the emitted restore line does not chmod 4755"
	fi
else
	bad "the ubi packer has no setuid restore — chown clears it and the console cannot become root"
fi

# The checks above are all MECHANISM: they read the packer's source. That is
# not enough, and this section exists because it was not enough on the bench.
# The fix was correct in the tracked master AND the image still shipped 755,
# because sysdrv/tools/pc/mtd-utils/Makefile COPIES mkfs_ubi.sh into
# output/out/sysdrv_out/pc/ and the build runs that copy — the same tracked-
# master/derived-copy split the buildroot defconfig has. A source-only gate
# passes while the artifact is broken.
#
# So: pack a tree containing a 4755 file for real, and read the mode back OUT
# of the packed image. A control file of known mode goes in alongside it, which
# is what proves the struct offsets rather than assuming them.
echo "== setuid survives a real ubi pack (end to end)"
MODEREAD=scripts/compliance/ubifs-mode.py
if [ ! -x "$UBIPACKER" ] || [ ! -f "$MODEREAD" ]; then
	bad "$UBIPACKER or $MODEREAD missing"
else
	mkdir -p "$TMP/suid/src/usr/sbin" "$TMP/suid/src/etc" "$TMP/suid/out"
	printf '#!/bin/sh\nexit 0\n' > "$TMP/suid/src/usr/sbin/media-gateway-privop"
	printf '#!/bin/sh\nexit 0\n' > "$TMP/suid/src/usr/sbin/satisense-privop"
	chmod 4755 "$TMP/suid/src/usr/sbin/media-gateway-privop" \
		   "$TMP/suid/src/usr/sbin/satisense-privop"
	echo hash > "$TMP/suid/src/etc/shadow"
	chmod 0600 "$TMP/suid/src/etc/shadow"
	if RK_DEBUG=1 "$UBIPACKER" "$TMP/suid/src" "$TMP/suid/out" \
		$((128 * 1024 * 1024)) rootfs ubifs lzo >"$TMP/suid/log" 2>&1 \
		&& [ -f "$TMP/suid/out/rootfs.img" ]; then
		_modes=$(python3 "$MODEREAD" "$TMP/suid/out/rootfs.img" \
			/etc/shadow /usr/sbin/media-gateway-privop /usr/sbin/satisense-privop 2>&1)
		# The control first: if this is not 0600 the offsets are wrong and
		# every other verdict from this reader is meaningless.
		if ! echo "$_modes" | grep -q '/etc/shadow .*perm=0600'; then
			bad "the mode reader is misreading the image (control /etc/shadow is not 0600): $(echo "$_modes" | tr '\n' ' ')"
		else
			_suid=$(echo "$_modes" | grep -c 'privop .*perm=4755')
			if [ "$_suid" -eq 2 ]; then
				ok "both dispatchers are 4755 in the packed image, not just in the source"
			else
				bad "only $_suid of 2 dispatchers kept setuid THROUGH the pack: $(echo "$_modes" | grep privop | tr '\n' ' ')"
			fi
		fi
	else
		bad "the ubi packer failed: $(tail -3 "$TMP/suid/log" | tr '\n' ' ')"
	fi
fi

# The stale-copy trap itself. mkfs_ubi.sh is copied into the output tree by
# sysdrv/tools/pc/mtd-utils/Makefile, and `cp -f` only re-runs when that target
# does — so a fix to the tracked master can sit there while every build keeps
# packing with the old script. That is exactly what happened on 2026-09-10: the
# fix was committed, the build was clean, and the image still had 755.
echo "== the derived ubi packer copy is not stale"
DERIVED=output/out/sysdrv_out/pc/mkfs_ubi.sh
if [ ! -f "$DERIVED" ]; then
	ok "no derived copy yet (nothing built) — nothing to be stale"
elif cmp -s "$UBIPACKER" "$DERIVED"; then
	ok "output/out/sysdrv_out/pc/mkfs_ubi.sh matches the tracked master"
else
	bad "the derived packer copy differs from $UBIPACKER — the build is packing with a STALE script; refresh it with: cp -f $UBIPACKER $DERIVED"
fi

# The SAME trap in the web layer. ab-boot/web/swu-install.sh reads as the
# master, but NOTHING copies it: each product Makefile installs its own
# submodule copy (web/cgi-lib/swu-install.sh), so an edit to the ab-boot file
# alone ships nothing while looking committed. Found 2026-09-11 fixing the
# install-error reporting. Same shape as the mkfs_ubi.sh trap above, different
# directory -- so gate it the same way rather than trusting anyone to remember.
echo "== the product copies of swu-install.sh match the ab-boot master"
SWUMASTER=media/joral/ab-boot/web/swu-install.sh
if [ ! -f "$SWUMASTER" ]; then
	ok "no ab-boot master present — nothing to diverge from"
else
	_drift=""
	for _c in media/joral/satisense-edge/web/cgi-lib/swu-install.sh \
	          media/joral/media-gateway/src/web/cgi-lib/swu-install.sh; do
		# A missing copy is a checked-out-shallow submodule, not drift.
		[ -f "$_c" ] || continue
		cmp -s "$SWUMASTER" "$_c" || _drift="$_drift $_c"
	done
	if [ -z "$_drift" ]; then
		ok "both product copies of swu-install.sh match $SWUMASTER"
	else
		bad "swu-install.sh drifted from the master in:$_drift — these are what actually ship; sync with: for f in$_drift; do cp -f $SWUMASTER \$f; done"
	fi
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
