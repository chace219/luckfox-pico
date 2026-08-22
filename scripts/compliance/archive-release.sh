#!/bin/bash
# archive-release.sh — put a release's compliance evidence somewhere that
# survives this workstation (EU CRA Regulation 2024/2847: Annex II asks for the
# version and build-ID scheme; Annex I Part II §1 for an SBOM per release; §2
# for the ability to say which builds an advisory affects).
#
# THE PROBLEM THIS EXISTS FOR. `./build.sh sbom` and `./build.sh cve` write into
# output/compliance/, which is in .gitignore, and no release was ever tagged.
# On 2026-08-22 that meant the only record tying release 2026.08.17 to commit
# 5a6f91d6a was a filename in an ignored directory on one machine. Losing it
# would not have been noticed by any gate, and an advisory arriving afterwards
# could not have been answered with "these builds are affected".
#
# WHAT IT COPIES, into media/joral/releases/<version>/ (tracked):
#   sbom.md / sbom.csv     the bill of materials for that build
#   cve-report.md          the findings and their dispositions
#   provenance.md          version, build ID, commit, submodule pins, date
#
# The cve-report CSV is deliberately NOT copied: ~1.8 MB per release of raw NVD
# records, reproducible from the .md's build ID and the cache. The .md carries
# every finding and every disposition, which is the reviewable artifact.
#
# WHAT IT REFUSES, because an archive nobody can trust is worse than none:
#   - an SBOM and a CVE report carrying DIFFERENT build IDs (they must describe
#     the same image — this is the exact drift that was found on 2026-08-22);
#   - a `-dirty` build ID (uncommitted work: the commit does not describe the
#     tree the image came from);
#   - a build ID whose commit is not an ancestor of HEAD (nothing to trace to);
#   - overwriting an existing archive without --force (a release's evidence is
#     written once; a second run means something is wrong).
#
# Usage:
#   scripts/compliance/archive-release.sh              # version from RELEASE_VERSION
#   scripts/compliance/archive-release.sh 2026.08.17   # or name it
#   scripts/compliance/archive-release.sh --force      # re-write an existing archive
#
# It does not commit or tag — see media/joral/release-build-runbook.md step 6.
set -euo pipefail

SDK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$SDK_DIR/output/compliance"
DEST_ROOT="$SDK_DIR/media/joral/releases"
FORCE=0
VERSION=""

while [ $# -gt 0 ]; do
	case "$1" in
		--force) FORCE=1 ;;
		-h|--help) sed -n '2,40p' "$0"; exit 0 ;;
		-*) echo "archive-release: unknown option '$1'" >&2; exit 1 ;;
		*) VERSION="$1" ;;
	esac
	shift
done

if [ -z "$VERSION" ]; then
	VERSION="$(sed -n '/^[0-9]/{p;q}' "$SDK_DIR/media/joral/RELEASE_VERSION")"
fi
case "$VERSION" in
	[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9]*) ;;
	*) echo "archive-release: '$VERSION' is not a YYYY.MM.PATCH release identity" >&2
	   exit 1 ;;
esac

fail() { echo "archive-release: $*" >&2; exit 1; }

newest() { ls -1t "$SRC_DIR"/$1 2>/dev/null | head -1; }

SBOM_MD="$(newest 'sbom-*.md')"
SBOM_CSV="$(newest 'sbom-*.csv')"
CVE_MD="$(newest 'cve-report-*.md')"

[ -n "$SBOM_MD" ] || fail "no SBOM in $SRC_DIR — run './build.sh sbom'"
[ -n "$CVE_MD" ]  || fail "no CVE report in $SRC_DIR — run './build.sh cve'"

# The build ID is the tail of the filename after the YYYY-MM-DD stamp.
build_id_of() { basename "$1" | sed -E 's/^[a-z-]+-[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/\.(md|csv)$//'; }

SBOM_ID="$(build_id_of "$SBOM_MD")"
CVE_ID="$(build_id_of "$CVE_MD")"
SBOM_CSV_ID="$(build_id_of "$SBOM_CSV")"

[ "$SBOM_ID" = "$CVE_ID" ] || fail "the SBOM and the CVE report describe different builds:
  SBOM        $SBOM_ID  ($(basename "$SBOM_MD"))
  CVE report  $CVE_ID  ($(basename "$CVE_MD"))
Regenerate both from the same image — that mismatch IS the finding this script was written for."
[ "$SBOM_ID" = "$SBOM_CSV_ID" ] || fail "the SBOM .md and .csv are from different runs ($SBOM_ID vs $SBOM_CSV_ID)"

case "$SBOM_ID" in
	*-dirty) fail "build ID '$SBOM_ID' is dirty — the artifacts describe a tree
that was never committed, so nothing can be traced back to it. Commit, rebuild,
regenerate, then archive." ;;
esac

# v1.0.0-177-g5a6f91d6a -> 5a6f91d6a
COMMIT="$(printf '%s\n' "$SBOM_ID" | sed -E 's/.*-g([0-9a-f]+)$/\1/')"
[ "$COMMIT" != "$SBOM_ID" ] || fail "cannot read a commit out of build ID '$SBOM_ID'"
git -C "$SDK_DIR" rev-parse --verify --quiet "$COMMIT^{commit}" >/dev/null \
	|| fail "commit $COMMIT is not in this repository"
git -C "$SDK_DIR" merge-base --is-ancestor "$COMMIT" HEAD \
	|| fail "commit $COMMIT is not an ancestor of HEAD — the artifacts come from
a build on another branch, or from work that has since been rewritten"

DEST="$DEST_ROOT/$VERSION"
if [ -d "$DEST" ] && [ "$FORCE" = "0" ]; then
	fail "$DEST already exists. A release's evidence is written once; pass
--force only if you know why you are replacing it."
fi
mkdir -p "$DEST"

cp "$SBOM_MD"  "$DEST/sbom.md"
cp "$SBOM_CSV" "$DEST/sbom.csv"
cp "$CVE_MD"   "$DEST/cve-report.md"

# If the SBOM's build ID was declared with --image-id rather than derived from
# the checkout, say so here. A declared ID passes every check above — it is
# clean and it names a real ancestor — so without this line the archive would
# present a reconstruction and an as-built record identically, and the flag
# would become a way to launder one into the other.
ID_NOTE=""
if grep -q 'Image build ID.*declared' "$SBOM_MD"; then
	ID_NOTE="the SBOM's build ID was **declared** with \`--image-id\`: it was regenerated from the unchanged Buildroot output of that build, at a later commit"
fi

FULL_SHA="$(git -C "$SDK_DIR" rev-parse "$COMMIT")"
COMMIT_SUBJECT="$(git -C "$SDK_DIR" log -1 --format=%s "$COMMIT")"
COMMIT_DATE="$(git -C "$SDK_DIR" log -1 --format=%cI "$COMMIT")"
BLOCKING="$(sed -n 's/^| Blocking findings | \([0-9]*\) |$/\1/p' "$CVE_MD" | head -1)"
VERDICT="$(sed -n 's/^| \*\*Verdict\*\* | \*\*\(.*\)\*\* |$/\1/p' "$CVE_MD" | head -1)"

{
	echo "# Release $VERSION — compliance evidence"
	echo
	echo "| | |"
	echo "|---|---|"
	echo "| Release | \`$VERSION\` |"
	echo "| Build ID | \`$SBOM_ID\` |"
	echo "| SDK commit | \`$FULL_SHA\` |"
	echo "| Commit subject | $COMMIT_SUBJECT |"
	echo "| Commit date | $COMMIT_DATE |"
	echo "| CVE gate | ${VERDICT:-unknown}, ${BLOCKING:-?} blocking |"
	echo "| Archived (UTC) | $(date -u +%Y-%m-%d) |"
	[ -n "$ID_NOTE" ] && echo "| Build ID provenance | $ID_NOTE |"
	echo
	echo "\`$VERSION\` is what a unit reports in \`/etc/sw-versions\` and what a"
	echo "\`.swu\` declares in its manifest. \`$SBOM_ID\` is what the SBOM and the"
	echo "CVE report stamp. This file is the only place the two are written down"
	echo "together, which is what makes \"is this unit affected\" answerable from"
	echo "a version an operator can read off a console."
	echo
	echo "## Submodule pins at that commit"
	echo
	echo "| Path | Commit |"
	echo "|---|---|"
	git -C "$SDK_DIR" ls-tree "$COMMIT" media/joral/ | \
		awk '$2 == "commit" { printf "| %s | `%s` |\n", $4, $3 }'
	echo
	echo "## Files here"
	echo
	echo "| File | What it is |"
	echo "|---|---|"
	echo "| \`sbom.md\` / \`sbom.csv\` | the bill of materials for this build (Annex I Part II §1) |"
	echo "| \`cve-report.md\` | findings and their dispositions at the gate (Annex I Part I §2, Part II §2) |"
	echo
	echo "The CVE report's CSV (~1.8 MB of raw NVD records) is not archived; it"
	echo "is reproducible from this build ID and the NVD cache, and every finding"
	echo "that mattered is in the .md with its disposition."
} > "$DEST/provenance.md"

echo "archive-release: wrote $DEST/{sbom.md,sbom.csv,cve-report.md,provenance.md}"
echo "archive-release: release $VERSION = build $SBOM_ID = commit $FULL_SHA"
echo "archive-release: now commit it and tag release/$VERSION (runbook step 6)"
