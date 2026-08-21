#!/bin/bash
# Drive the shipped post-build hardening script — CRA Annex I #1/#4, plan
# item 13.
#
# check-board-hardening.sh asserts that every board profile SELECTS this script.
# This asserts what the script then DOES, against synthetic staging trees,
# because two of its three actions became conditional on 2026-08-21 when it went
# from two profiles to all sixteen:
#
#   - the /oem loader path is removed only where the oem payload was stripped.
#     On the BSP camera profiles RkEnv.sh is load-bearing — the generated
#     S21appinit sources it and rkipc resolves librockit through the
#     LD_LIBRARY_PATH it sets — so removing it there would harden a board by
#     breaking it. Getting that condition backwards is silent in both
#     directions: on a product image a surviving RkEnv.sh reopens the exposure
#     closed in 2026.08.6, and on a camera image a missing one breaks the app.
#
#   - the unauthenticated console shell (`respawn:-/bin/sh`) is removed in
#     addition to the getty. Only the fastboot profiles carried it, and their
#     inittab arrives by overlay AFTER this script runs — so the shipped file is
#     asserted statically by the gate, and the script's own handling is asserted
#     here, since a buildroot skeleton could grow one at any BSP bump.
#
# Usage: test-board-hardening.sh
set -u
cd "$(dirname "$0")/../.." || exit 2

HARDEN=project/cfg/BoardConfig_IPC/luckfox-hardening-post.sh

pass=0; fail=0
ok()  { echo "ok   — $1"; pass=$((pass+1)); }
bad() { echo "FAIL — $1"; fail=$((fail+1)); }

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

[ -f "$HARDEN" ] || { echo "FAIL — $HARDEN missing"; exit 1; }

# stage <name> <oem-has-libs?> [inittab-extra-line]
stage() {
	local d="$TMP/$1" libs=$2 extra=${3:-}
	mkdir -p "$d/rootfs/etc/init.d" "$d/rootfs/etc/profile.d" "$d/rootfs/etc/stunnel" "$d/oem"
	echo "export LD_LIBRARY_PATH=/oem/usr/lib:/oem/lib" > "$d/rootfs/etc/profile.d/RkEnv.sh"
	echo "sample" > "$d/rootfs/etc/stunnel/stunnel.conf"
	echo "stunnel init" > "$d/rootfs/etc/init.d/S50stunnel"
	{
		echo "::sysinit:/etc/init.d/rcS"
		echo "console::respawn:/sbin/getty -L  console 0 vt100 # GENERIC_SERIAL"
		[ -n "$extra" ] && echo "$extra"
		echo "::shutdown:/etc/init.d/rcK"
	} > "$d/rootfs/etc/inittab"
	if [ "$libs" = withlibs ]; then
		mkdir -p "$d/oem/usr/lib"
		echo "so" > "$d/oem/usr/lib/librockit.so"
	fi
	echo "$d"
}

run_harden() {
	local d=$1 script=${2:-$HARDEN}
	RK_PROJECT_PACKAGE_ROOTFS_DIR="$d/rootfs" RK_PROJECT_PACKAGE_OEM_DIR="$d/oem" \
		bash "$script" >"$TMP/out" 2>&1
}

echo "== A stripped oem: the loader path goes"
A=$(stage a nolibs)
run_harden "$A"; rc=$?
if [ $rc -eq 0 ] && [ ! -e "$A/rootfs/etc/profile.d/RkEnv.sh" ]; then
	ok "A: RkEnv.sh removed when /oem carries no libraries"
else
	bad "A: exit $rc, RkEnv.sh still present — the 2026.08.6 exposure would reopen"
fi
if [ ! -e "$A/rootfs/etc/init.d/S50stunnel" ] && [ ! -d "$A/rootfs/etc/stunnel" ]; then
	ok "A: the buildroot stunnel sample init and config are removed"
else
	bad "A: the stray stunnel sample survived"
fi
if ! grep -q getty "$A/rootfs/etc/inittab"; then
	ok "A: the serial getty is removed"
else
	bad "A: the getty survived"
fi

echo "== A camera profile keeps what it loads"
B=$(stage b withlibs)
run_harden "$B"; rc=$?
if [ $rc -eq 0 ] && [ -e "$B/rootfs/etc/profile.d/RkEnv.sh" ]; then
	ok "B: RkEnv.sh kept when /oem still carries libraries"
else
	bad "B: exit $rc, RkEnv.sh removed from a profile that resolves libraries through it"
fi
if grep -q 'keeping RkEnv.sh' "$TMP/out"; then
	ok "B: the decision is stated in the build log, not silent"
else
	bad "B: nothing in the log says why the file was kept"
fi
if ! grep -q getty "$B/rootfs/etc/inittab"; then
	ok "B: the getty is removed on camera profiles too"
else
	bad "B: the getty survived on a camera profile"
fi

echo "== An unauthenticated console shell is removed as well"
C=$(stage c nolibs '::respawn:-/bin/sh')
run_harden "$C"
if ! grep -qE '^[^#]*respawn:-?/bin/sh' "$C/rootfs/etc/inittab"; then
	ok "C: respawn:-/bin/sh removed"
else
	bad "C: a root shell with no authentication survived the hardening pass"
fi
if grep -q 'console shell' "$TMP/out"; then
	ok "C: its removal is reported separately from the getty's"
else
	bad "C: the console-shell removal is not reported"
fi

echo "== A missing inittab fails the build rather than being skipped"
D=$(stage d nolibs); rm -f "$D/rootfs/etc/inittab"
run_harden "$D"; rc=$?
if [ $rc -ne 0 ]; then
	ok "D: exit $rc — a hardening step that cannot run stops the build"
else
	bad "D: exit 0 with no inittab — a silently skipped step is indistinguishable from one that ran"
fi

echo "== Mutations of the shipped script (each MUST fail a case above)"
# Rewriting the multi-line condition is fragile; make the keep-branch
# unconditional instead, which is the same defect a reversed test would be.
M1="$TMP/m1"; awk '{ if ($0 ~ /^	if \[ -d "\$RK_PROJECT_PACKAGE_OEM_DIR\/usr\/lib" \]/) { print "\tif true; then"; skip=1; next } if (skip && $0 ~ /^	   \[ -d/) next; skip=0; print }' "$HARDEN" > "$M1"
A1=$(stage a1 nolibs)
run_harden "$A1" "$M1"
if [ -e "$A1/rootfs/etc/profile.d/RkEnv.sh" ]; then
	ok "mutation: keep-branch made unconditional — case A fails, as it must"
else
	bad "mutation: the condition is not what decides the removal"
fi

M2="$TMP/m2"; sed 's|^	if \[ -d "\$RK_PROJECT_PACKAGE_OEM_DIR/usr/lib" \] |	if false \&\& [ -d "$RK_PROJECT_PACKAGE_OEM_DIR/usr/lib" ] |' "$HARDEN" > "$M2"
B2=$(stage b2 withlibs)
run_harden "$B2" "$M2"
if [ ! -e "$B2/rootfs/etc/profile.d/RkEnv.sh" ]; then
	ok "mutation: guard disabled — case B fails, as it must"
else
	bad "mutation: disabling the guard did not remove RkEnv.sh from a camera profile"
fi

# Disable the console-shell branch at its guard — deleting the block by regex
# is what the first version of this mutation tried, and it silently deleted
# nothing.
M3="$TMP/m3"; awk 'BEGIN{done=0} { if (!done && $0 ~ /if grep -qE .\^\[\^#\]\*respawn/) { print "\tif false; then"; done=1; next } print }' "$HARDEN" > "$M3"
C3=$(stage c3 nolibs '::respawn:-/bin/sh')
run_harden "$C3" "$M3"
if grep -qE '^[^#]*respawn:-?/bin/sh' "$C3/rootfs/etc/inittab"; then
	ok "mutation: console-shell removal deleted — case C fails, as it must"
else
	bad "mutation: the console shell went away without the code that removes it"
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
