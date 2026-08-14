#!/bin/sh
# fw-key-ceremony.sh — generate the Joral firmware-signing keyset.
#
# Implements Part A.2 of media/joral/firmware-signing-and-support-policy.md:
# TWO RSA-4096 keypairs (active + rollover spare) with self-signed 20-year
# certificates, in one sitting.
#
# RUN THIS ONLY ON THE OFFLINE CEREMONY MACHINE (fresh live-USB boot,
# network hardware disabled). It refuses to run if it detects a default
# route, as a seatbelt — absence of a route is NOT proof of isolation, the
# procedure is.
#
#   sh fw-key-ceremony.sh <output-dir>
#
# Output layout:
#   <out>/private/joral-fw-2026-a.key.pem   -> hardware tokens / LUKS sticks,
#   <out>/private/joral-fw-2026-b.key.pem      then SHRED from disk (the
#                                              script prints the commands)
#   <out>/public/joral-fw-2026-a.crt.pem    -> commit to the repo
#   <out>/public/joral-fw-2026-b.crt.pem    -> commit to the repo
#   <out>/public/trusted-certs.pem          -> both certs; ships in the image
#                                              at /etc/swupdate/trusted-certs.pem
#   <out>/ceremony-minute.txt               -> fill in names/serials, sign,
#                                              file in the technical file
#
# Private keys are AES-256 encrypted with ONE passphrase known to the two
# holders (policy A.2/A.3). openssl prompts twice per key — same passphrase
# for both keys.
set -eu

OUT=${1:?usage: fw-key-ceremony.sh <output-dir>}
YEAR=$(date +%Y)
NAME_A="joral-fw-${YEAR}-a"
NAME_B="joral-fw-${YEAR}-b"
DAYS=7300   # 20 years: cert expiry must never be the thing that bricks updates

# Seatbelt, not proof: refuse if this machine plainly has a network.
if ip route 2>/dev/null | grep -q default; then
	echo "REFUSING: this machine has a default route — not the offline ceremony machine." >&2
	exit 1
fi

umask 077
mkdir -p "$OUT/private" "$OUT/public"

for N in "$NAME_A" "$NAME_B"; do
	echo "== generating $N (RSA-4096, encrypted; enter the shared passphrase) =="
	openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
		-aes-256-cbc -out "$OUT/private/$N.key.pem"
	openssl req -new -x509 -days "$DAYS" -sha256 \
		-key "$OUT/private/$N.key.pem" \
		-subj "/O=Joral LLC/OU=Firmware Signing/CN=$N" \
		-out "$OUT/public/$N.crt.pem"
done

cat "$OUT/public/$NAME_A.crt.pem" "$OUT/public/$NAME_B.crt.pem" \
	> "$OUT/public/trusted-certs.pem"

{
	echo "Joral firmware signing key ceremony — minute"
	echo "Date (UTC): $(date -u '+%Y-%m-%d %H:%M')"
	echo "Machine: offline live-USB session (policy A.2)"
	echo "Present: ______________________  ______________________"
	echo ""
	echo "Keys generated:"
	for N in "$NAME_A" "$NAME_B"; do
		echo "  $N"
		echo "    cert sha256: $(openssl x509 -in "$OUT/public/$N.crt.pem" -outform DER | openssl dgst -sha256 | cut -d' ' -f2)"
	done
	echo ""
	echo "Private-key media (fill in serials):"
	echo "  SET 1 (office safe):  token A ________  token B ________"
	echo "  SET 2 (off-site):     token A ________  token B ________"
	echo ""
	echo "Signatures: ______________________  ______________________"
} > "$OUT/ceremony-minute.txt"

echo ""
echo "== done =="
echo "1. Copy $OUT/private/*.key.pem to the four tokens/sticks, VERIFY each copy reads back,"
echo "   then destroy the disk copies:"
echo "     shred -u $OUT/private/*.key.pem"
echo "2. Take $OUT/public/ to the repo on the transfer stick; commit all three PEMs."
echo "3. Fill in and sign $OUT/ceremony-minute.txt; file it in the technical file."
