#!/bin/sh
# test_misc_ab.sh — host test for misc_ab against a scratch file image.
#
# Pins the on-disk contract to the bootloader's implementation
# (common/spl/spl_ab.c) rather than to our own code:
#   1. byte-exact init record — magic, versions, slot defaults, and a CRC32
#      verified INDEPENDENTLY (python zlib), at byte offset 2048
#   2. spl_get_current_slot() selection semantics, including the tie rule
#   3. spl_ab_decrease_tries() try-burning: unproven slots pay per boot,
#      successful slots boot free, exhaustion falls back to the other slot
#   4. self-recovery from a corrupt record, like spl_ab_data_read()
#   5. the mark-* verbs used by SWUpdate, the health check and the console
#
# Pure host: everything is pread/pwrite on a plain file.
set -u

DIR="$(dirname "$0")"
BIN="${MISC_AB:-$DIR/../build/misc_ab}"
T="$(mktemp -d /tmp/misc_ab.XXXXXX)"
trap 'rm -rf "$T"' EXIT
IMG="$T/misc.img"

fails=0
ok() {
	if [ "$1" -eq 0 ]; then printf '  %-58s ok\n' "$2"
	else printf '  %-58s FAIL\n' "$2"; fails=$((fails + 1)); fi
}

fresh() { dd if=/dev/zero of="$IMG" bs=1024 count=8 2>/dev/null; }
sel()   { "$BIN" select "$IMG" 2>/dev/null; }
stat_field() { "$BIN" status "$IMG" | grep "^$1" ; }

[ -x "$BIN" ] || { echo "build misc_ab first (make -C $DIR/.. test)"; exit 1; }

echo "test_misc_ab (bootloader A/B contract):"

# ---- 1. byte-exact init record ---------------------------------------------
fresh
"$BIN" init "$IMG"; ok $? "init exits 0"

python3 - "$IMG" <<'EOF'
import sys, zlib
raw = open(sys.argv[1], 'rb').read()
rec = raw[2048:2048+32]
assert rec[0:4] == b'\x00AB0', f"magic {rec[0:4]!r}"
assert rec[4] == 1 and rec[5] == 0, "version"
assert rec[8:12]  == bytes([15, 7, 0, 0]), f"slot a {rec[8:12]!r}"
assert rec[12:16] == bytes([14, 7, 0, 0]), f"slot b {rec[12:16]!r}"
assert rec[16] == 0, "last_boot"
crc = int.from_bytes(rec[28:32], 'big')
assert crc == zlib.crc32(rec[:28]) & 0xffffffff, "crc32 mismatch"
# nothing before offset 2048 may be touched (bootloader BCB space)
assert raw[:2048] == b'\x00' * 2048, "wrote below AB_METADATA_OFFSET"
EOF
ok $? "init record byte-exact at offset 2048 (independent CRC32)"

# ---- 2. selection semantics --------------------------------------------------
[ "$(sel)" = "a" ]; ok $? "fresh record: A wins (priority 15 vs 14)"

fresh; "$BIN" init "$IMG"; "$BIN" mark-active "$IMG" b
[ "$(sel)" = "b" ]; ok $? "mark-active b: B wins the next boot"

fresh; "$BIN" init "$IMG"; "$BIN" mark-unbootable "$IMG" a
[ "$(sel)" = "b" ]; ok $? "A unbootable: B chosen"

# ---- 3. try burning ----------------------------------------------------------
fresh; "$BIN" init "$IMG"
for i in 1 2 3 4 5 6 7; do sel >/dev/null; done
stat_field slot_a | grep -q "tries_remaining=0"
ok $? "7 selects burn all 7 tries of the unproven slot"
[ "$(sel)" = "b" ]; ok $? "8th boot falls back to B (A exhausted, never successful)"

fresh; "$BIN" init "$IMG"; "$BIN" mark-successful "$IMG" a
sel >/dev/null; sel >/dev/null
stat_field slot_a | grep -q "successful_boot=1"
ok $? "successful slot boots without burning anything"
[ "$(sel)" = "a" ]; ok $? "successful slot keeps winning"

# rollback story end-to-end: update to B, B never proves itself, A returns
fresh; "$BIN" init "$IMG"
"$BIN" mark-successful "$IMG" a
"$BIN" mark-active "$IMG" b
for i in 1 2 3 4 5 6 7; do sel >/dev/null; done
[ "$(sel)" = "a" ]; ok $? "failed update: exhausted B rolls back to proven A"

# ---- 4. corrupt record recovers ----------------------------------------------
fresh
printf 'GARBAGE-NOT-A-RECORD' | dd of="$IMG" bs=1 seek=2048 conv=notrunc 2>/dev/null
[ "$(sel)" = "a" ]; ok $? "corrupt record: select recovers to defaults, picks A"
"$BIN" status "$IMG" | grep -q "choice=a"
ok $? "recovered record persisted (status agrees after reopen)"

# ---- 5. last_boot fallback ----------------------------------------------------
fresh; "$BIN" init "$IMG"
"$BIN" mark-unbootable "$IMG" a
"$BIN" mark-active "$IMG" b        # make B the active one...
for i in 1 2 3 4 5 6 7; do sel >/dev/null; done   # ...and exhaust it
[ "$(sel)" = "b" ]; ok $? "no bootable slot: last_boot breaks the tie"

if [ "$fails" -eq 0 ]; then echo "all misc_ab tests passed"; exit 0
else echo "FAILED: $fails check(s)"; exit 1; fi
