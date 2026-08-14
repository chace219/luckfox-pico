#!/bin/sh
# fw-sign.sh — sign (offline) or verify (anywhere) a firmware release.
#
# Implements Part A.4 of media/joral/firmware-signing-and-support-policy.md.
# SWUpdate verifies a CMS/PKCS#7 detached signature over sw-description;
# this script produces and checks exactly that, so what the offline laptop
# signs is what the device enforces.
#
#   fw-sign.sh sign   <sw-description> <private-key.pem> <signer-cert.pem>
#       (OFFLINE laptop) -> writes <sw-description>.sig, prompts for the
#       key passphrase. Prints the sha256 of both files for the signing log.
#
#   fw-sign.sh verify <sw-description> <sw-description.sig> <trusted-certs.pem>
#       (build machine, release gate) -> exit 0 iff the signature chains to
#       a cert in the trust bundle — the same check the unit performs.
set -eu

CMD=${1:?usage: fw-sign.sh sign|verify ...}

case "$CMD" in
sign)
	SWDESC=${2:?sw-description}; KEY=${3:?private key}; CERT=${4:?signer cert}
	openssl cms -sign -in "$SWDESC" -out "$SWDESC.sig" -outform DER \
		-inkey "$KEY" -signer "$CERT" -nosmimecap -binary
	echo "signed: $SWDESC.sig"
	echo "for the signing log (docs/compliance/signing-log.md):"
	echo "  sw-description sha256: $(openssl dgst -sha256 "$SWDESC" | cut -d' ' -f2)"
	echo "  signature      sha256: $(openssl dgst -sha256 "$SWDESC.sig" | cut -d' ' -f2)"
	;;
verify)
	SWDESC=${2:?sw-description}; SIG=${3:?signature}; TRUST=${4:?trusted certs pem}
	# -purpose any: self-signed signing certs, not TLS certs.
	if openssl cms -verify -inform DER -in "$SIG" -content "$SWDESC" \
		-CAfile "$TRUST" -purpose any -binary -out /dev/null 2>/dev/null; then
		echo "OK: signature valid against $TRUST"
	else
		echo "FAIL: signature does NOT verify against $TRUST" >&2
		exit 1
	fi
	;;
*)
	echo "usage: fw-sign.sh sign <sw-description> <key> <cert>" >&2
	echo "       fw-sign.sh verify <sw-description> <sig> <trusted-certs.pem>" >&2
	exit 1
	;;
esac
