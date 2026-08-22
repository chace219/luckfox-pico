#!/bin/bash
# gen-sbom.sh — build the Software Bill of Materials for a Joral edge firmware
# image (EU CRA Regulation 2024/2847, Annex I Part II §1: "identify and
# document components contained in the product, including by drawing up a
# software bill of materials").
#
# Three sources, because no single one covers the image:
#
#   1. PLATFORM layer — Buildroot's own `make legal-info`, which enumerates
#      every package it built (version, license, license files, upstream
#      source site) from the actual .config used for this image. Authoritative
#      and free: Buildroot already tracks this metadata per package.
#   2. PLATFORM EXTRAS — everything in the image that legal-info cannot see:
#      the kernel, U-Boot, the Rockchip bootloader blobs and media SDK (not
#      Buildroot packages at all), plus the Buildroot-INTERNAL packages that
#      carry no source archive — the rootfs skeleton, the init and network
#      scripts, and the external-toolchain wrapper that ships uClibc-ng,
#      libgcc and libstdc++. Declared in scripts/compliance/platform-extra.csv.
#   3. APPLICATION layer — Buildroot knows nothing about our own daemons, the
#      EIPScanner submodule that is cross-built and statically linked, or the
#      vendored headers. Those are declared by hand in each product tree as
#      docs/compliance/app-manifest.csv and merged in here.
#
# Source 2 was missing until 2026-08-22, and its absence was not visible from
# inside this script: cve-check.py has always added the same components to the
# CVE inventory from its own cpe-extra.csv, so the CVE report checked the
# kernel, U-Boot and the vendor SDK while the SBOM listed none of them — and
# the CVE report's header claimed both "describe the same image by
# construction". The two declaration files are now cross-checked below and a
# disagreement fails this script rather than producing a quieter SBOM.
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
#   scripts/compliance/gen-sbom.sh --image-id X # stamp X as the build ID
#
# --image-id reconstructs the SBOM of an image that is already packed, when the
# tree has moved past the commit it was built at (doc commits after a release
# cut, typically). It is a claim about the Buildroot output, not about the
# checkout, so the generated document says out loud that the ID was declared
# rather than derived. Do not use it to describe an image that was never built.
#
# `./build.sh sbom` calls this. It is a REPORTING step: it never modifies the
# image, so it is safe to run after a build (and cheap with --reuse).
set -euo pipefail

SDK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BR_DIR="$(echo "$SDK_DIR"/sysdrv/source/buildroot/buildroot-* | awk '{print $1}')"
OUT_DIR="$SDK_DIR/output/compliance"
REUSE=0
IMAGE_ID_OVERRIDE=""

# Product trees contributing an application-layer manifest.
PRODUCTS=(media/joral/satisense-edge media/joral/media-gateway)

# The two hand-declared platform files, cross-checked against each other below.
PLATFORM_EXTRA="$SDK_DIR/scripts/compliance/platform-extra.csv"
CPE_EXTRA="$SDK_DIR/scripts/compliance/cpe-extra.csv"

while [ $# -gt 0 ]; do
	case "$1" in
		--reuse) REUSE=1 ;;
		-o) shift; OUT_DIR="$1" ;;
		--image-id) shift; IMAGE_ID_OVERRIDE="$1" ;;
		-h|--help) sed -n '2,52p' "$0"; exit 0 ;;
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
ID_SOURCE="derived from the checkout"
if [ -n "$IMAGE_ID_OVERRIDE" ]; then
	echo "gen-sbom: NOTE build ID declared as '$IMAGE_ID_OVERRIDE' (checkout says '$IMAGE_ID')" >&2
	IMAGE_ID="$IMAGE_ID_OVERRIDE"
	ID_SOURCE="**declared** with --image-id, not derived from the checkout"
fi
BUILD_DATE="$(date -u +%Y-%m-%d)"
STAMP="$BUILD_DATE-$IMAGE_ID"

# The release identity a UNIT reports (/etc/sw-versions) and a .swu declares.
# The git describe above names a tree; this names the thing in the field, and an
# advisory has to be answerable in both currencies.
RELEASE_VERSION="$(sed -n '/^[0-9]/{p;q}' "$SDK_DIR/media/joral/RELEASE_VERSION" 2>/dev/null || true)"
[ -n "$RELEASE_VERSION" ] || RELEASE_VERSION="unknown"

mkdir -p "$OUT_DIR"
cp "$LEGAL/manifest.csv"      "$OUT_DIR/manifest-platform.csv"
cp "$LEGAL/host-manifest.csv" "$OUT_DIR/manifest-host.csv" 2>/dev/null || true
cp "$LEGAL/buildroot.config"  "$OUT_DIR/buildroot.config"  2>/dev/null || true

CSV="$OUT_DIR/sbom-$STAMP.csv"
MD="$OUT_DIR/sbom-$STAMP.md"

# ---- 1b. the two hand-declared platform files must agree ---------------------
# cve-check.py ADDS a component to the CVE inventory when a cpe-extra.csv row
# names something Buildroot has never heard of. Those same components have to
# be in the SBOM, or the two documents describe different products — which is
# exactly what happened between 2026-08-06 and 2026-08-22, unnoticed, because
# nothing compared them. This does, and it fails the build in both directions:
# a component checked but not listed, and a component listed but not checked.
[ -f "$PLATFORM_EXTRA" ] || {
	echo "gen-sbom: $PLATFORM_EXTRA is missing — the kernel, U-Boot, the" >&2
	echo "gen-sbom: bootloader blobs and the C library come from that file" >&2
	exit 1
}
python3 - "$OUT_DIR/manifest-platform.csv" "$PLATFORM_EXTRA" "$CPE_EXTRA" \
	"${PRODUCTS[@]/#/$SDK_DIR/}" <<'PYEOF' || exit 1
import csv, os, sys

def rows(path):
    """DictReader tolerant of the `#` comment lines these files carry, quoted
    or not — the same convention cve-check.py's csv_rows() reads."""
    with open(path, newline="", encoding="utf-8") as f:
        lines = [ln for ln in f
                 if not ln.lstrip().startswith("#")
                 and not ln.lstrip().startswith('"#')]
    return list(csv.DictReader(lines))

manifest, extra_path, cpe_path = sys.argv[1], sys.argv[2], sys.argv[3]
products = sys.argv[4:]

# What Buildroot's own manifest already covers.
known = set()
with open(manifest, newline="", encoding="utf-8") as f:
    rd = csv.reader(f)
    next(rd, None)
    for r in rd:
        if r:
            known.add(r[0].strip())
# What the products declare.
for p in products:
    m = os.path.join(p, "docs/compliance/app-manifest.csv")
    if os.path.exists(m):
        for r in rows(m):
            known.add((r.get("COMPONENT") or "").strip())

# A cpe-extra row is an ADDED component only when nothing else declares it;
# rows that merely attach a CPE to a Buildroot package are not our business.
cpe_added = {}
for r in rows(cpe_path):
    n = (r.get("COMPONENT") or "").strip()
    if n and n not in known:
        cpe_added[n] = (r.get("VERSION") or "").strip()
sbom_added = {}
for r in rows(extra_path):
    n = (r.get("COMPONENT") or "").strip()
    if n:
        sbom_added[n] = (r.get("VERSION") or "").strip()

fail = []
for n in sorted(set(cpe_added) - set(sbom_added)):
    fail.append("  %s is CVE-checked (cpe-extra.csv) but absent from the SBOM "
                "(platform-extra.csv)" % n)
for n in sorted(set(sbom_added) - set(cpe_added)):
    fail.append("  %s is in the SBOM (platform-extra.csv) but not in the CVE "
                "inventory (cpe-extra.csv)" % n)
for n in sorted(set(cpe_added) & set(sbom_added)):
    if cpe_added[n] != sbom_added[n]:
        fail.append("  %s: cpe-extra.csv says %r, platform-extra.csv says %r"
                    % (n, cpe_added[n], sbom_added[n]))
if fail:
    print("gen-sbom: the SBOM and the CVE inventory disagree about what is in "
          "the image:", file=sys.stderr)
    print("\n".join(fail), file=sys.stderr)
    print("gen-sbom: fix both files. A component in one and not the other is "
          "the defect this check exists for.", file=sys.stderr)
    sys.exit(1)
print("gen-sbom: %d added platform components agree with cpe-extra.csv"
      % len(sbom_added))
PYEOF

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
	# Platform extras: in the image, invisible to legal-info. Emitted verbatim,
	# same six columns, already cross-checked against cpe-extra.csv above.
	grep -v '^[[:space:]]*"\?#' "$PLATFORM_EXTRA" | tail -n +2 | grep -v '^[[:space:]]*$' || true
	# Application layer, per product. First-party rows declare their VERSION as
	# the token @PRODUCT_BUILD_ID@ and we substitute that product's own build
	# identifier here — the same string the binary reports via --version and the
	# console shows. Written this way round on purpose: the manifests stay
	# declarative (no git in a checked-in CSV, nothing to forget to bump) and the
	# git call lives in exactly one place.
	#
	# Before this, those rows read "unversioned — see SDK build ID", which was
	# true when neither product had a version and is now simply wrong. An SBOM
	# whose first-party components carry no version cannot answer the one
	# question it exists to answer: is THIS unit affected by that advisory?
	for p in "${PRODUCTS[@]}"; do
		m="$SDK_DIR/$p/docs/compliance/app-manifest.csv"
		if [ -f "$m" ]; then
			pid="$(git -C "$SDK_DIR/$p" describe --always --dirty --tags 2>/dev/null || echo unknown)"
			tail -n +2 "$m" | grep -v '^[[:space:]]*$' | \
				sed "s/@PRODUCT_BUILD_ID@/$pid/g" || true
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
	echo "| Release | \`$RELEASE_VERSION\` — the version a unit reports and a \`.swu\` declares |"
	echo "| Image build ID | \`$IMAGE_ID\` ($ID_SOURCE) |"
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
	echo "The platform layer is Buildroot's \`legal-info\` manifest **plus**"
	echo "\`scripts/compliance/platform-extra.csv\`, which carries what"
	echo "\`legal-info\` cannot see: the kernel, U-Boot, the Rockchip bootloader"
	echo "blobs and media SDK, and the Buildroot-internal packages that ship the"
	echo "rootfs skeleton and the C library. Those components are cross-checked"
	echo "against \`cpe-extra.csv\` at generation time, so this document and the"
	echo "CVE report cannot describe different products."
	echo
	echo "## Licenses present (platform layer)"
	echo
	echo "| License | Components |"
	echo "|---|---|"
	grep '^"platform"' "$CSV" | \
		awk -F'","' 'NF>=4 {print $4}' | \
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
	# The kernel is the other dated component, and it is the one the A/B
	# updater cannot replace. Read the declared version rather than asserting
	# it, same as OpenSSL above, so this line changes when the re-base does.
	awk -F'","' '/^"platform","linux-kernel"/ {
		v=$3;
		if (v ~ /^5\.10\./)
			printf "| linux-kernel | %s | **upstream 5.10 stable EOL Dec 2026** — re-base trigger and options in `media/joral/kernel-currency-plan.md`; travels in the single-copy boot FIT, so a move is a reflash, not a `.swu` |\n", v
		else
			printf "| linux-kernel | %s | supported branch |\n", v
	}' "$PLATFORM_EXTRA"
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
	echo "Generated from the merged CSV, not from Buildroot's manifest alone —"
	echo "the rows marked *(not a Buildroot package)* are the ones a"
	echo "\`legal-info\`-only SBOM was silently missing."
	echo
	echo "| Component | Version | License | Origin |"
	echo "|---|---|---|---|"
	# NOTES ($6) is the discriminator: the Buildroot rows this script emits all
	# carry the literal "buildroot package" there, so anything else came from
	# platform-extra.csv. ORIGIN ($5) is a source URL for the former and a tree
	# path for the latter, which is why it cannot be the test.
	grep '^"platform"' "$CSV" | \
		awk -F'","' 'NF>=6 {
			n=$6; sub(/"[[:space:]]*$/,"",n);
			printf "| %s | %s | %s | %s |\n", $2, $3, $4,
				(n == "buildroot package" ? "buildroot package" : $5 " *(not a Buildroot package)*")
		}'
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
