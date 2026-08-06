#!/bin/bash
# gen-sbom.sh — build the Software Bill of Materials for a Joral edge firmware
# image (EU CRA Regulation 2024/2847, Annex I Part II §1: "identify and
# document components contained in the product, including by drawing up a
# software bill of materials").
#
# Two sources, because no single one covers the image:
#
#   1. PLATFORM layer — Buildroot's own `make legal-info`, which enumerates
#      every package it built (version, license, license files, upstream
#      source site) from the actual .config used for this image. Authoritative
#      and free: Buildroot already tracks this metadata per package.
#   2. APPLICATION layer — Buildroot knows nothing about components that are
#      NOT Buildroot packages: our own daemons, the EIPScanner submodule that
#      is cross-built and statically linked, vendored headers, and the
#      Rockchip vendor blobs shipped in the media SDK. Those are declared by
#      hand in each product tree as docs/compliance/app-manifest.csv and
#      merged in here.
#
# Output (default $SDK/output/compliance/, override with -o):
#   sbom-<image-id>.csv   one row per component, both layers, machine-readable
#   sbom-<image-id>.md    the same content as a reviewable document, with the
#                         license roll-up and an end-of-life callout
#   manifest-platform.csv  Buildroot's target manifest, verbatim
#   manifest-host.csv      Buildroot's host-tool manifest (build-time only,
#                          not shipped in the image — kept for provenance)
#   buildroot.config       the exact package configuration behind the above
#
# Deliberately NOT copied: legal-info's sources/ tree (~400 MB of upstream
# tarballs). That is a source-redistribution artifact, not part of an SBOM;
# generate it on demand for a license request instead.
#
# Usage:
#   scripts/compliance/gen-sbom.sh              # refresh legal-info, then build
#   scripts/compliance/gen-sbom.sh --reuse      # reuse existing legal-info
#   scripts/compliance/gen-sbom.sh -o DIR       # write elsewhere
#
# `./build.sh sbom` calls this. It is a REPORTING step: it never modifies the
# image, so it is safe to run after a build (and cheap with --reuse).
set -euo pipefail

SDK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BR_DIR="$(echo "$SDK_DIR"/sysdrv/source/buildroot/buildroot-* | awk '{print $1}')"
OUT_DIR="$SDK_DIR/output/compliance"
REUSE=0

# Product trees contributing an application-layer manifest.
PRODUCTS=(media/joral/satisense-edge media/joral/media-gateway)

while [ $# -gt 0 ]; do
	case "$1" in
		--reuse) REUSE=1 ;;
		-o) shift; OUT_DIR="$1" ;;
		-h|--help) sed -n '2,40p' "$0"; exit 0 ;;
		*) echo "gen-sbom: unknown argument '$1'" >&2; exit 1 ;;
	esac
	shift
done

[ -d "$BR_DIR" ] || {
	echo "gen-sbom: no Buildroot tree under $SDK_DIR/sysdrv/source/buildroot" >&2
	echo "gen-sbom: run './build.sh sysdrv' first — the SBOM describes a BUILT image" >&2
	exit 1
}
[ -f "$BR_DIR/.config" ] || {
	echo "gen-sbom: $BR_DIR has no .config — run './build.sh sysdrv' first" >&2
	exit 1
}

LEGAL="$BR_DIR/output/legal-info"

# ---- 1. platform layer ------------------------------------------------------
# legal-info re-verifies every package's source archive, so it is slow (tens of
# minutes on a cold dl/ cache). --reuse skips it when the existing output is
# still the one that matches .config.
if [ "$REUSE" = "1" ] && [ -f "$LEGAL/manifest.csv" ]; then
	echo "gen-sbom: reusing $LEGAL/manifest.csv"
elif [ "$REUSE" = "1" ]; then
	echo "gen-sbom: --reuse given but no legal-info output exists yet — generating" >&2
	REUSE=0
fi
if [ "$REUSE" = "0" ]; then
	echo "gen-sbom: running buildroot legal-info (this takes a while)"
	BR2_EXTERNAL="$SDK_DIR/sysdrv/tools/board/buildroot/br2-external" \
		make -C "$BR_DIR" legal-info >/dev/null
fi
[ -f "$LEGAL/manifest.csv" ] || {
	echo "gen-sbom: legal-info produced no manifest.csv" >&2; exit 1; }

# ---- image identity ---------------------------------------------------------
# The SBOM must name the thing it describes. Same scheme as the Annex II fact
# sheets: SDK git describe + UTC build date. An SBOM without a build ID cannot
# be matched to a deployed unit, which is the whole point of having one.
IMAGE_ID="$(git -C "$SDK_DIR" describe --always --dirty --tags 2>/dev/null || echo unknown)"
BUILD_DATE="$(date -u +%Y-%m-%d)"
STAMP="$BUILD_DATE-$IMAGE_ID"

mkdir -p "$OUT_DIR"
cp "$LEGAL/manifest.csv"      "$OUT_DIR/manifest-platform.csv"
cp "$LEGAL/host-manifest.csv" "$OUT_DIR/manifest-host.csv" 2>/dev/null || true
cp "$LEGAL/buildroot.config"  "$OUT_DIR/buildroot.config"  2>/dev/null || true

CSV="$OUT_DIR/sbom-$STAMP.csv"
MD="$OUT_DIR/sbom-$STAMP.md"

# ---- 2. merge both layers into one CSV --------------------------------------
# Columns are a subset of Buildroot's, plus LAYER and ORIGIN so a reader can
# tell a platform package from something we ship ourselves.
{
	echo '"LAYER","COMPONENT","VERSION","LICENSE","ORIGIN","NOTES"'
	# Buildroot target packages: strip its header, keep pkg/version/license,
	# carry the upstream source site as ORIGIN.
	tail -n +2 "$OUT_DIR/manifest-platform.csv" | \
		awk -F'","' 'NF>=6 {
			gsub(/^"/,"",$1); gsub(/"$/,"",$6);
			printf "\"platform\",\"%s\",\"%s\",\"%s\",\"%s\",\"buildroot package\"\n", $1, $2, $3, $6
		}'
	# Application layer, per product.
	for p in "${PRODUCTS[@]}"; do
		m="$SDK_DIR/$p/docs/compliance/app-manifest.csv"
		if [ -f "$m" ]; then
			tail -n +2 "$m" | grep -v '^[[:space:]]*$' || true
		else
			echo "gen-sbom: WARNING no app-manifest.csv in $p — application-layer components for that product are MISSING from this SBOM" >&2
		fi
	done
} > "$CSV"

PLATFORM_N=$(grep -c '^"platform"' "$CSV" || true)
APP_N=$(grep -vc '^"platform"' "$CSV" || true)
APP_N=$((APP_N - 1))   # discount the header row
HOST_N=0
[ -f "$OUT_DIR/manifest-host.csv" ] && HOST_N=$(($(wc -l < "$OUT_DIR/manifest-host.csv") - 1))

# ---- 3. human-readable document --------------------------------------------
{
	echo "# Software Bill of Materials — Joral edge firmware"
	echo
	echo "| | |"
	echo "|---|---|"
	echo "| Image build ID | \`$IMAGE_ID\` |"
	echo "| Generated (UTC) | $BUILD_DATE |"
	echo "| Generator | \`scripts/compliance/gen-sbom.sh\` |"
	echo "| Platform components (in image) | $PLATFORM_N |"
	echo "| Application components (in image) | $APP_N |"
	echo "| Host/build-time components (not shipped) | $HOST_N |"
	echo
	echo "Covers both products built from this SDK — they share one Buildroot"
	echo "rootfs, so the platform layer is common; the application layer is"
	echo "labelled per product. Machine-readable form: \`$(basename "$CSV")\`."
	echo "Regenerate with \`./build.sh sbom\` after any image build."
	echo
	echo "## Licenses present (platform layer)"
	echo
	echo "| License | Components |"
	echo "|---|---|"
	tail -n +2 "$OUT_DIR/manifest-platform.csv" | \
		awk -F'","' 'NF>=3 {print $3}' | sed 's/"$//' | \
		sort | uniq -c | sort -rn | \
		awk '{n=$1; $1=""; sub(/^ /,""); printf "| %s | %d |\n", $0, n}'
	echo
	echo "## Components with known end-of-life or advisory status"
	echo
	echo "Flagged here because Annex I Part II §2 requires vulnerabilities in"
	echo "components to be addressed without delay, which starts with knowing"
	echo "which components no longer receive upstream fixes."
	echo
	echo "| Component | Version | Status |"
	echo "|---|---|---|"
	# OpenSSL 1.1.1 went EOL 2023-09-11; grep the real built version rather
	# than asserting it, so this line stops firing once we migrate.
	awk -F'","' '/^"libopenssl"/ || /^"openssl"/ {
		gsub(/^"/,"",$1);
		if ($2 ~ /^1\.1\.1/)
			printf "| %s | %s | **EOL since 2023-09-11** — no upstream security fixes; migration tracked in ADR-127 |\n", $1, $2
		else
			printf "| %s | %s | supported branch |\n", $1, $2
	}' "$OUT_DIR/manifest-platform.csv"
	echo
	echo "## Application layer"
	echo
	echo "| Product | Component | Version | License | Origin |"
	echo "|---|---|---|---|---|"
	grep -v '^"platform"' "$CSV" | tail -n +2 | \
		awk -F'","' 'NF>=5 {
			gsub(/^"/,"",$1); gsub(/"$/,"",$5);
			printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5
		}'
	echo
	echo "## Platform layer"
	echo
	echo "| Component | Version | License |"
	echo "|---|---|---|"
	tail -n +2 "$OUT_DIR/manifest-platform.csv" | \
		awk -F'","' 'NF>=3 { gsub(/^"/,"",$1); l=$3; sub(/"$/,"",l);
			printf "| %s | %s | %s |\n", $1, $2, l }'
	echo
	echo "---"
	echo
	echo "Source archives for the platform layer are not included here (~400 MB)."
	echo "Buildroot keeps them under \`sysdrv/source/buildroot/*/output/legal-info/sources/\`"
	echo "after generation — use that tree to answer a copyleft source request."
} > "$MD"

echo "gen-sbom: wrote $CSV"
echo "gen-sbom: wrote $MD"
echo "gen-sbom: $PLATFORM_N platform + $APP_N application components (build $IMAGE_ID)"
