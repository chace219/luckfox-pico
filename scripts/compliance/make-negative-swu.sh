#!/bin/bash
# Build the three negative-test update packages for the SWUpdate verification
# legs (swupdate-implementation-plan.md verification items 3 and 4; compliance
# plan remaining-work item 8d).
#
# Row #7 "update mechanism" is currently evidenced by GOOD updates only. What
# decides whether it survives contact with a BAD one is whether verification
# refuses, and refuses *before writing anything to the standby slot* — a
# rejection that happens after the write has begun still leaves a half-written
# slot behind.
#
# Three packages, because they fail at three different places and a single
# "corrupt file" test would not tell them apart:
#
#   tampered-payload    the rootfs image is altered, sw-description and its
#                       signature are untouched and VALID. Fails on the sha256
#                       recorded in sw-description. This is the realistic
#                       attack: a signature proves who wrote the manifest, not
#                       that the bytes streaming past match it.
#   tampered-signature  sw-description is untouched, its detached CMS signature
#                       is altered. Fails in CMS verification.
#   wrong-key           sw-description is re-signed with a DIFFERENT, perfectly
#                       valid key. Structurally sound, correctly signed, and
#                       must still be refused — this is what proves the trust
#                       store is doing the deciding rather than mere presence
#                       of a signature.
#
# Usage: make-negative-swu.sh <good.swu> [outdir]
#   Default outdir is output/image/negative-tests/.
#
# The artifacts are DELIBERATELY not committed: they are 120 MB each and are
# reproducible from any release in seconds. Regenerate against the release you
# are actually testing — a negative test built from a different release proves
# nothing about the one on the bench.
set -eu

GOOD=${1:?usage: make-negative-swu.sh <good.swu> [outdir]}
OUT=${2:-output/image/negative-tests}
[ -f "$GOOD" ] || { echo "no such package: $GOOD" >&2; exit 2; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# SWUpdate requires sw-description FIRST in the archive, so member order is
# preserved explicitly rather than relying on the shell's glob order.
( cd "$WORK" && cpio -idm --quiet < "$OLDPWD/$GOOD" )
ORDER=$(cd "$WORK" && cpio -it --quiet < "$OLDPWD/$GOOD")

repack() { # repack <srcdir> <dest.swu>
	( cd "$1" && printf '%s\n' $ORDER | cpio -o -H crc --quiet ) > "$2"
}

# --- 1. tampered payload -----------------------------------------------------
# One byte, deep inside the image so it cannot be confused with a header or
# length field. The manifest and signature stay valid and untouched.
P="$WORK/../payload"; rm -rf "$P"; cp -a "$WORK" "$P"
IMG=$(cd "$P" && ls *.img | head -1)
SZ=$(stat -c '%s' "$P/$IMG")
printf '\xff' | dd of="$P/$IMG" bs=1 seek=$((SZ / 2)) count=1 conv=notrunc status=none
repack "$P" "$OUT/tampered-payload.swu"

# --- 2. tampered signature ---------------------------------------------------
S="$WORK/../signature"; rm -rf "$S"; cp -a "$WORK" "$S"
SSZ=$(stat -c '%s' "$S/sw-description.sig")
printf '\xff' | dd of="$S/sw-description.sig" bs=1 seek=$((SSZ / 2)) count=1 conv=notrunc status=none
repack "$S" "$OUT/tampered-signature.swu"

# --- 3. wrong key ------------------------------------------------------------
# A throwaway key of the same shape as the real one. The package is internally
# consistent and correctly signed; only the signer is wrong.
W="$WORK/../wrongkey"; rm -rf "$W"; cp -a "$WORK" "$W"
openssl req -x509 -newkey rsa:3072 -nodes -days 30 \
	-keyout "$W/.k.pem" -out "$W/.c.pem" \
	-subj "/CN=NOT-THE-JORAL-SIGNING-KEY" 2>/dev/null
openssl cms -sign -in "$W/sw-description" -out "$W/sw-description.sig" \
	-signer "$W/.c.pem" -inkey "$W/.k.pem" \
	-outform DER -nosmimecap -binary 2>/dev/null
rm -f "$W/.k.pem" "$W/.c.pem"
repack "$W" "$OUT/wrong-key.swu"

# --- 4. unorderable version ---------------------------------------------------
# NOT a corruption test. This package is perfectly valid and CORRECTLY SIGNED
# with the DEV key the image trusts — verification must PASS. What it exercises
# is the layer after verification: a version the unit cannot compare against its
# own. swu-version.sh requires exactly three numeric fields with a 4-digit year
# and 2-digit month, so "1.0.0" is what a package built before release numbering
# looks like, and sw_version_order() answers `unknown`.
#
# The rule it proves is that `unknown` is treated as needing confirmation rather
# than as safe. A gate that silently allowed what it could not order would be
# bypassed by the oldest packages in existence — exactly the ones an advisory
# would be about.
K=media/joral/ab-boot/keys-dev/dev-signing.key.pem
C=media/joral/ab-boot/keys-dev/dev-signing.crt.pem
if [ -f "$K" ] && [ -f "$C" ]; then
	U="$WORK/../unorderable"; rm -rf "$U"; cp -a "$WORK" "$U"
	sed -i 's/^\(\s*version = \)"[^"]*";/\1"1.0.0";/' "$U/sw-description"
	openssl cms -sign -in "$U/sw-description" -out "$U/sw-description.sig" \
		-signer "$C" -inkey "$K" -outform DER -nosmimecap -binary 2>/dev/null
	repack "$U" "$OUT/unorderable-version.swu"
	UNORDERABLE=yes
else
	echo "note — DEV signing key absent, skipping unorderable-version.swu" >&2
	UNORDERABLE=no
fi

echo "negative-test packages in $OUT:"
LIST="tampered-payload tampered-signature wrong-key"
[ "$UNORDERABLE" = yes ] && LIST="$LIST unorderable-version"
for f in $LIST; do
	printf '  %-22s %s  sha256 %s\n' "$f.swu" \
		"$(stat -c '%s' "$OUT/$f.swu")" \
		"$(sha256sum "$OUT/$f.swu" | cut -c1-16)"
done
echo
echo "All three MUST be refused. Expected failure points differ:"
echo "  tampered-payload    sha256 mismatch on the image (manifest signature is VALID)"
echo "  tampered-signature  CMS verification"
echo "  wrong-key           CMS verification against the trust store"
echo
echo "unorderable-version.swu is DIFFERENT: it must VERIFY and then be refused"
echo "by the ORDERING gate (order=unknown), asking for the DOWNGRADE phrase."
