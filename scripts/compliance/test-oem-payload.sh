#!/bin/bash
# Guard the two runtime halves of the oem strip — CRA Annex I #4, plan item 14.
#
# The build-side hook is asserted by check-oem-payload.sh against the packed
# images. This drives the two INIT SCRIPTS, which no image check can reach:
# S22oemclean, which is what makes the change effective on a unit that was
# flashed before it (oem is not in the .swu payload, so the update carries the
# script and not the empty partition), and S52npu, which loads the NPU driver
# the BSP left stranded on that partition.
#
# Both are driven through their $OEM_STATE_ROOT / $NPU_STATE_ROOT prefixes, so
# the logic exercised is the logic that ships, and every case is re-run against
# a mutated copy of the shipped script to prove the case can fail.
#
# Usage: test-oem-payload.sh [rootfs-staging-dir ...]
set -u
cd "$(dirname "$0")/../.." || exit 2

INIT=project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/etc/init.d
CLEAN="$INIT/S22oemclean"
NPU="$INIT/S52npu"

pass=0; fail=0
ok()  { echo "ok   — $1"; pass=$((pass+1)); }
bad() { echo "FAIL — $1"; fail=$((fail+1)); }

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

[ -f "$CLEAN" ] || { echo "FAIL — $CLEAN missing"; exit 1; }
[ -f "$NPU" ]   || { echo "FAIL — $NPU missing"; exit 1; }

# A recording insmod, so "did it try to load, and with what path" is observable
# without a kernel.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/insmod" <<'STUB'
#!/bin/sh
echo "$@" >> "$INSMOD_LOG"
exit 0
STUB
chmod +x "$TMP/bin/insmod"
PATH="$TMP/bin:$PATH"
export PATH

KREL=$(uname -r)

# seed_oem <root> <mounted?> — a fielded unit's /oem, with the payload shapes
# actually observed on one: a directory tree, a top-level file, a dotfile, and
# the filesystem's own lost+found.
seed_oem() {
	local root=$1 mounted=$2
	mkdir -p "$root/oem/usr/bin" "$root/oem/usr/ko" "$root/oem/lost+found" "$root/proc"
	echo "rkipc" > "$root/oem/usr/bin/rkipc"
	echo "mod"   > "$root/oem/usr/ko/rknpu.ko"
	echo "stale" > "$root/oem/stale-file"
	echo "hidden" > "$root/oem/.hidden"
	if [ "$mounted" = mounted ]; then
		printf '/dev/root / ext4 rw 0 0\n/dev/mmcblk0p7 /oem ext4 rw 0 0\n' > "$root/proc/mounts"
	else
		printf '/dev/root / ext4 rw 0 0\n' > "$root/proc/mounts"
	fi
}

run_clean() {
	local root=$1 script=${2:-$CLEAN}
	OEM_STATE_ROOT="$root" OEM_MOUNTS_FILE="$root/proc/mounts" \
		sh "$script" start >"$TMP/clean.out" 2>&1
}

oem_entries() { find "$1/oem" -mindepth 1 | grep -v 'lost+found' | wc -l; }

echo "== S22oemclean"

echo "-- A mounted /oem is purged, and lost+found is left alone"
A="$TMP/a"; seed_oem "$A" mounted
run_clean "$A"
if [ "$(oem_entries "$A")" -eq 0 ]; then
	ok "A: the inherited payload is gone"
else
	bad "A: payload survived: $(find "$A/oem" -mindepth 1 | tr '\n' ' ')"
fi
if [ -d "$A/oem/lost+found" ]; then
	ok "A: lost+found kept — the filesystem's own directory is not payload"
else
	bad "A: lost+found was deleted"
fi
if [ ! -e "$A/oem/.hidden" ]; then
	ok "A: dotfiles are purged too"
else
	bad "A: a dotfile survived — a payload that hides from a bare glob is still payload"
fi
if grep -q 'removed 3 ' "$TMP/clean.out"; then
	ok "A: the count of top-level entries is reported, so the log distinguishes 'nothing there' from 'did nothing'"
else
	bad "A: no count in the output: $(cat "$TMP/clean.out")"
fi

echo "-- An UNMOUNTED /oem is left alone and reported"
# The mountpoint directory exists in the rootfs whether or not S20linkmount
# worked. A bare existence test would purge the rootfs copy and report success —
# the same trap finding A's key persistence had to be gated against.
B="$TMP/b"; seed_oem "$B" unmounted
run_clean "$B"
if [ "$(oem_entries "$B")" -gt 0 ]; then
	ok "B: nothing was purged while /oem was not mounted"
else
	bad "B: purged an unmounted mountpoint — that is the rootfs, not the partition"
fi
if grep -qi 'not mounted' "$TMP/clean.out"; then
	ok "B: the degraded case is reported, not silent"
else
	bad "B: no report of the unmounted case: $(cat "$TMP/clean.out")"
fi

echo "-- A second boot is a no-op that still succeeds"
run_clean "$A"
if [ $? -eq 0 ] && [ "$(oem_entries "$A")" -eq 0 ]; then
	ok "C: idempotent — a cleaned unit stays clean and start still succeeds"
else
	bad "C: the second run failed or changed something"
fi
if grep -q 'nothing to purge' "$TMP/clean.out" && ! grep -q 'removed' "$TMP/clean.out"; then
	ok "C: a clean unit still logs that the control ran, and reports no removal"
else
	bad "C: the clean path is silent or claims a removal — silence cannot distinguish 'ran, nothing to do' from 'never ran'"
fi

echo "-- Mutations of the shipped script (each MUST fail the case above)"
mutate() { sed "$1" "$2" > "$3"; }

M1="$TMP/m1"; mutate 's|^	awk -v d="/oem".*|	[ -d "$OEM_DIR" ]|' "$CLEAN" "$M1"
B1="$TMP/b1"; seed_oem "$B1" unmounted
run_clean "$B1" "$M1"
if [ "$(oem_entries "$B1")" -eq 0 ]; then
	ok "mutation: mount gate weakened to a directory test — case B fails, as it must"
else
	bad "mutation: weakening the mount gate did NOT break case B — the gate is not load-bearing"
fi

M2="$TMP/m2"; mutate 's|"\$OEM_DIR"/\* "\$OEM_DIR"/\.\*|"$OEM_DIR"/*|' "$CLEAN" "$M2"
A2="$TMP/a2"; seed_oem "$A2" mounted
run_clean "$A2" "$M2"
if [ -e "$A2/oem/.hidden" ]; then
	ok "mutation: dotfiles dropped from the glob — case A fails, as it must"
else
	bad "mutation: the dotfile was still purged — the .* half of the glob is dead code"
fi

M3="$TMP/m3"; mutate 's|^KEEP="lost+found"|KEEP="lost+found usr stale-file .hidden"|' "$CLEAN" "$M3"
A3="$TMP/a3"; seed_oem "$A3" mounted
run_clean "$A3" "$M3"
if [ "$(oem_entries "$A3")" -gt 0 ]; then
	ok "mutation: keep-list broadened — case A fails, as it must"
else
	bad "mutation: broadening the keep list purged anyway — the list is not consulted"
fi

echo
echo "== S52npu"

seed_npu() {
	local root=$1 with_module=$2 with_dev=$3
	mkdir -p "$root/dev" "$root/sys/module"
	if [ "$with_module" = module ]; then
		mkdir -p "$root/lib/modules/$KREL"
		echo "ko" > "$root/lib/modules/$KREL/rknpu.ko"
	fi
	[ "$with_dev" = dev ] && : > "$root/dev/rknpu"
	return 0
}

run_npu() {
	local root=$1 script=${2:-$NPU}
	INSMOD_LOG="$TMP/insmod.log" NPU_STATE_ROOT="$root" \
		sh "$script" load >"$TMP/npu.out" 2>&1
}

echo "-- The module is loaded from the rootfs, under the running release"
N="$TMP/n"; seed_npu "$N" module dev
: > "$TMP/insmod.log"
run_npu "$N"
if grep -q "$N/lib/modules/$KREL/rknpu.ko" "$TMP/insmod.log"; then
	ok "E: insmod called with /lib/modules/$KREL/rknpu.ko"
else
	bad "E: insmod was not called with the rootfs module path: $(cat "$TMP/insmod.log")"
fi
if grep -q "/dev/rknpu present" "$TMP/npu.out"; then
	ok "E: the device node is confirmed, not assumed"
else
	bad "E: the device node was not reported: $(cat "$TMP/npu.out")"
fi

echo "-- A missing module is not an error"
F="$TMP/f"; seed_npu "$F" nomodule nodev
: > "$TMP/insmod.log"
run_npu "$F"; rc=$?
if [ $rc -eq 0 ] && [ ! -s "$TMP/insmod.log" ]; then
	ok "F: no module, no insmod, boot continues"
else
	bad "F: exit $rc / insmod log '$(cat "$TMP/insmod.log")' — an absent accelerator must not fail a boot"
fi

echo "-- An already-loaded module is not loaded twice"
G="$TMP/g"; seed_npu "$G" module dev; mkdir -p "$G/sys/module/rknpu"
: > "$TMP/insmod.log"
run_npu "$G"
if [ ! -s "$TMP/insmod.log" ]; then
	ok "G: already loaded, so nothing was inserted"
else
	bad "G: insmod ran against a loaded module"
fi

echo "-- Loaded but no device node names the real cause"
# This is the state of every unit flashed before the dtb change: the module
# inserts, the npu node is disabled, probe never runs, /dev/rknpu never appears.
# The fix for it is a reflash, and the log has to say so or the next person
# debugs the module.
H="$TMP/h"; seed_npu "$H" module nodev
: > "$TMP/insmod.log"
run_npu "$H"
if grep -q 'device-tree node is disabled' "$TMP/npu.out" && grep -q 'reflash' "$TMP/npu.out"; then
	ok "H: the absent device node is reported as a dtb/reflash problem"
else
	bad "H: the absent device node was not explained: $(cat "$TMP/npu.out")"
fi

echo "-- Mutations of the shipped script (each MUST fail the case above)"
M4="$TMP/m4"; mutate 's|^KREL=$(uname -r)|KREL=5.10.0-not-this-kernel|' "$NPU" "$M4"
: > "$TMP/insmod.log"
run_npu "$N" "$M4"
if [ ! -s "$TMP/insmod.log" ]; then
	ok "mutation: fixed kernel release — case E fails, as it must"
else
	bad "mutation: a wrong release still found a module — the lookup is not release-scoped"
fi

M5="$TMP/m5"; mutate '/if \[ -d "\$SYS_MODULE" \]; then/,+3d' "$NPU" "$M5"
: > "$TMP/insmod.log"
run_npu "$G" "$M5"
if [ -s "$TMP/insmod.log" ]; then
	ok "mutation: already-loaded check removed — case G fails, as it must"
else
	bad "mutation: removing the loaded check changed nothing"
fi

M6="$TMP/m6"; mutate 's|	if \[ -e "\$DEV_NODE" \]; then|	if true; then|' "$NPU" "$M6"
run_npu "$H" "$M6"
if ! grep -q 'device-tree node is disabled' "$TMP/npu.out"; then
	ok "mutation: device check short-circuited — case H fails, as it must"
else
	bad "mutation: the device check is not what produced the H message"
fi

if [ $# -gt 0 ]; then
	echo
	echo "== Staging / packed trees carry the same scripts"
	for tree in "$@"; do
		[ -d "$tree" ] || { echo "skip — $tree not built"; continue; }
		for s in S22oemclean S52npu; do
			t="$tree/etc/init.d/$s"
			if [ ! -f "$t" ]; then
				bad "$(basename "$tree"): no $s"
			elif cmp -s "$t" "$INIT/$s"; then
				ok "$(basename "$tree"): $s matches the overlay"
			else
				bad "$(basename "$tree"): $s differs from the overlay — the image is not what this file guards"
			fi
		done
	done
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
