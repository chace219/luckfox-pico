#!/bin/sh
# test_swu_version.sh — contract tests for the release-identity library.
#
# The library decides whether an install is a downgrade, so a wrong answer here
# is not a cosmetic bug: "older" read as "newer" would let a signed rollback to
# a known-vulnerable release install with no warning, which is the exact defect
# one-way door #4 exists to close.
#
# Run from ab-boot's `make test`. Every filesystem-touching check uses the
# SW_VERSIONS_FILE injection seam, so the SHIPPED functions are the tested
# functions — no reimplementation to drift.
#
#   sh tests/test_swu_version.sh
set -u

LIB=${LIB:-"$(dirname "$0")/../web/swu-version.sh"}
[ -r "$LIB" ] || { echo "FAIL: cannot read $LIB"; exit 1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
check() { # check <description> <expected> <actual>
	if [ "$2" = "$3" ]; then ok; else bad "$1 — expected '$2', got '$3'"; fi
}
yes_() { # yes_ <description> <command...>  — expects success
	_d=$1; shift
	if "$@" >/dev/null 2>&1; then ok; else bad "$_d (expected success)"; fi
}
no_() { # no_ <description> <command...>  — expects failure
	_d=$1; shift
	if "$@" >/dev/null 2>&1; then bad "$_d (expected failure)"; else ok; fi
}

# Point the library at scratch state before sourcing it.
SW_VERSIONS_FILE="$TMP/sw-versions"
export SW_VERSIONS_FILE
. "$LIB"

echo "== format validation =="
for v in 2026.08.1 2026.01.0 2000.12.999 2030.10.42 9999.12.1; do
	yes_ "valid: $v" sw_version_valid "$v"
done
for v in \
	'' '2026.08' '2026' '2026.08.1.2' '26.08.1' '2026.8.1' '2026.13.1' \
	'2026.00.1' 'v1.0.0-66-g2d4b29958' '2d4b29958' '2026.08.x' '2026.08.' \
	'.08.1' '2026.08.1-dirty' '1999.08.1' 'unknown' '2026 08 1'
do
	no_ "invalid: '$v'" sw_version_valid "$v"
done

echo "== ordering =="
check "same release"            same  "$(sw_version_order 2026.08.1 2026.08.1)"
check "patch up"                newer "$(sw_version_order 2026.08.1 2026.08.2)"
check "patch down"              older "$(sw_version_order 2026.08.2 2026.08.1)"
check "month up"                newer "$(sw_version_order 2026.08.9 2026.09.1)"
check "month down"              older "$(sw_version_order 2026.09.1 2026.08.9)"
check "year up"                 newer "$(sw_version_order 2026.12.9 2027.01.1)"
check "year down"               older "$(sw_version_order 2027.01.1 2026.12.9)"

# THE case a string compare gets backwards: "2026.08.10" sorts BEFORE
# "2026.08.9" lexicographically. The tenth patch of a month is not exotic, and
# getting it wrong silently inverts the gate for exactly the releases that have
# seen the most fixes.
check "double-digit patch is newer" newer "$(sw_version_order 2026.08.9 2026.08.10)"
check "double-digit patch reverse"  older "$(sw_version_order 2026.08.10 2026.08.9)"
check "patch 2 vs 10"               newer "$(sw_version_order 2026.08.2 2026.08.10)"
# Same trap one field up: month 9 vs 10, and a zero-padded month must not be
# read as octal.
check "month 09 vs 10"              newer "$(sw_version_order 2026.09.1 2026.10.1)"
check "month 08 vs 09"              newer "$(sw_version_order 2026.08.1 2026.09.1)"

echo "== unorderable inputs =="
check "hash running"     unknown "$(sw_version_order v1.0.0-66-g2d4b29958 2026.08.1)"
check "hash candidate"   unknown "$(sw_version_order 2026.08.1 2d4b29958-dirty)"
check "empty running"    unknown "$(sw_version_order '' 2026.08.1)"
check "empty candidate"  unknown "$(sw_version_order 2026.08.1 '')"
check "both missing"     unknown "$(sw_version_order '' '')"
# Always exactly one word, always exit 0 — callers branch on the word, and a
# non-zero exit here would be swallowed differently by every caller's shell.
check "one word only"    1 "$(sw_version_order '' '' | wc -w | tr -d ' ')"
yes_  "order always exits 0" sw_version_order garbage garbage

echo "== confirmation gate =="
no_  "newer needs no confirm"    sw_version_needs_confirm newer
no_  "same needs no confirm"     sw_version_needs_confirm same
yes_ "older needs confirm"       sw_version_needs_confirm older
# The default must be SAFE: anything the comparator could not order has to
# require the operator, never fall through as permitted.
yes_ "unknown needs confirm"     sw_version_needs_confirm unknown
yes_ "empty needs confirm"       sw_version_needs_confirm ''
yes_ "garbage needs confirm"     sw_version_needs_confirm nonsense

echo "== running version =="
no_ "absent file is not a version" sw_version_running
printf 'rootfs 2026.08.1\n' > "$SW_VERSIONS_FILE"
check "reads the rootfs entry" 2026.08.1 "$(sw_version_running)"
printf 'other 2030.01.5\nrootfs 2026.08.1\nrootfs 2099.01.1\n' > "$SW_VERSIONS_FILE"
check "picks the right name, first match" 2026.08.1 "$(sw_version_running)"
printf 'other 2030.01.5\n' > "$SW_VERSIONS_FILE"
no_ "no rootfs entry is not a version" sw_version_running
: > "$SW_VERSIONS_FILE"
no_ "empty file is not a version" sw_version_running
# An image built before this scheme has no such file. That must read as
# unorderable — NOT as "no downgrade" — or the gate is open on exactly the
# units that predate it.
rm -f "$SW_VERSIONS_FILE"
check "pre-scheme image is unorderable" \
	unknown "$(sw_version_order "$(sw_version_running || echo '')" 2026.08.1)"

echo "== version out of a .swu =="
mkswu() { # mkswu <file> <sw-description body>
	_d="$TMP/swu.$$"
	rm -rf "$_d"; mkdir -p "$_d"
	printf '%s\n' "$2" > "$_d/sw-description"
	: > "$_d/rootfs.img"
	# crc is the format ./build.sh swu packs, and busybox cpio on the device
	# reads it (magic 070702, verified). Fall back to newc only because
	# busybox's own cpio applet cannot CREATE crc — and busybox ash runs
	# applets in place of PATH binaries, so the archive format here depends on
	# which shell is running the suite. The format is not what is under test;
	# the extraction is, and both formats exercise the same code path.
	( cd "$_d" && printf 'sw-description\nrootfs.img\n' |
		cpio -o -H crc --quiet 2>/dev/null ) > "$1"
	if [ ! -s "$1" ]; then
		( cd "$_d" && printf 'sw-description\nrootfs.img\n' |
			cpio -o -H newc --quiet 2>/dev/null ) > "$1"
	fi
	rm -rf "$_d"
}
mkswu "$TMP/a.swu" 'software = {
	version = "2026.08.3";
	description = "Joral edge platform rootfs (build v1.0.0-66-g2d4b29958)";
};'
check "reads the manifest version" 2026.08.3 "$(sw_version_from_swu "$TMP/a.swu")"

# The match is anchored at the field NAME. An unanchored '.*version = "' also
# fires on any field whose name merely ENDS in version, and with head -n1 the
# gate would then compare against whichever of those came first in the file —
# silently, and against a real version string, so nothing downstream looks
# wrong. Guarded here because the manifest is expected to grow fields.
mkswu "$TMP/b.swu" 'software = {
	previous_version = "2019.01.1";
	description = "Joral edge platform rootfs (build v1.0.0-66-g2d4b29958)";
	version = "2026.09.1";
};'
check "ignores a field whose name ends in version" 2026.09.1 "$(sw_version_from_swu "$TMP/b.swu")"

no_ "missing file is not a version"  sw_version_from_swu "$TMP/nope.swu"
: > "$TMP/empty.swu"
no_ "empty file is not a version"    sw_version_from_swu "$TMP/empty.swu"
mkswu "$TMP/c.swu" 'software = { description = "no version at all"; };'
no_ "manifest without a version"     sw_version_from_swu "$TMP/c.swu"

echo "== stamping the image =="
REL="$TMP/RELEASE_VERSION"
OUT="$TMP/stamped/etc/sw-versions"
printf '# the platform release identity\n2026.08.1\n' > "$REL"
check "stamp returns the version" 2026.08.1 "$(sw_version_stamp "$REL" "$OUT")"
check "stamp writes SWUpdate's format" "rootfs 2026.08.1" "$(cat "$OUT")"
# Round trip: what was stamped is what a unit running that image reports.
check "stamped image reports itself" 2026.08.1 \
	"$(SW_VERSIONS_FILE="$OUT" sh -c '. "'"$LIB"'"; sw_version_running')"

# A malformed RELEASE_VERSION must FAIL THE BUILD. Shipping an image whose
# version cannot be ordered recreates the defect this whole file closes, and it
# would not be visible until an operator tried to install over it.
rm -f "$OUT"
printf 'v1.0.0-66-g2d4b29958\n' > "$REL"
no_ "refuses a git hash"        sw_version_stamp "$REL" "$OUT"
[ -f "$OUT" ] && bad "refused stamp still wrote $OUT" || ok
printf '2026.13.1\n' > "$REL"
no_ "refuses an impossible month" sw_version_stamp "$REL" "$OUT"
printf '# only a comment\n\n' > "$REL"
no_ "refuses a version-less file" sw_version_stamp "$REL" "$OUT"
no_ "refuses a missing file"      sw_version_stamp "$TMP/absent" "$OUT"
[ -f "$OUT" ] && bad "refused stamp wrote $OUT" || ok

printf '   2026.08.7   # bumped for the August respin\n' > "$REL"
check "tolerates whitespace and trailing comments" 2026.08.7 \
	"$(sw_version_stamp "$REL" "$OUT")"

echo
echo "swu-version: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
