#!/bin/bash
# Every commit a compliance document cites as closed must actually ship.
#
# On 2026-08-12 two commits were pushed to a branch whose PR had already
# merged — one per product repository, 30 seconds apart. Both were real, both
# were tested, and both sat on a branch that no later PR picked up. The
# compliance documents recorded the behaviour as delivered: media-gateway's
# Annex I row 6 read "met on both transports" for four days while the UDP
# attribution code was not an ancestor of any release, and the SatiSense manual
# described a firewall the shipped PDFs did not mention for six.
#
# Nothing in the existing suites could have caught it. They test the tree in
# front of them, and the tree in front of you on a feature branch is correct —
# that is the whole trap. The check has to be about ancestry, not content.
#
# Three questions, in the order they can fail:
#
#   A. Did the cited commit LAND?   ancestor of its repo's default branch
#   B. Does it SHIP?                ancestor of the submodule revision this
#                                   superproject pins — the image a customer
#                                   receives is the pinned revision, not the
#                                   submodule's branch tip
#   C. Is the pin itself sane?      the pinned revision is an ancestor of the
#                                   submodule's default branch, i.e. we are not
#                                   shipping something that only exists on a
#                                   feature branch
#
# B and C are separate on purpose. A commit can be merged (A passes) and still
# not be in the release, because the submodule pointer was never bumped — which
# is the ordinary end of every submodule PR and the thing most likely to be
# forgotten.
#
# Usage: check-cited-commits.sh [--ref <superproject-rev>]
#   --ref  evaluate the pins recorded at some other revision (default HEAD),
#          so a release tag can be audited after the fact.
#
# A short hex token in backticks is treated as a commit only if some repository
# actually resolves it as one; register keys, hashes and 0xFF00-style constants
# therefore drop out without needing an exclusion list. A token no repository
# knows is reported separately — it is either a typo or a commit that was never
# pushed anywhere, and both are worth a human look.
#
# CONVENTION THIS ESTABLISHES: in a compliance document, a backticked SHA is a
# claim that the commit ships. Write it that way only when you mean that. A SHA
# mentioned as history — "the work was orphaned as 1a7bd8e and recovered" —
# goes in plain prose without backticks, because it is describing something
# that by definition is not in the release. Backticks are the assertion; this
# script is what makes the assertion cost something.
set -u
cd "$(dirname "$0")/../.." || exit 2

REF=HEAD
[ "${1:-}" = "--ref" ] && { REF="${2:?--ref needs a revision}"; }

SUBMODULES="media/joral/media-gateway media/joral/satisense-edge"
# Documents an assessor reads, and the plan they are rolled up into.
DOCS="media/joral/cra-compliance-plan.md"
for s in $SUBMODULES; do
	DOCS="$DOCS $s/docs/compliance/cra-annex1-matrix.md"
	DOCS="$DOCS $s/docs/compliance/cra-annex2-facts.md"
done

pass=0; fail=0
ok()   { echo "ok   — $1"; pass=$((pass+1)); }
bad()  { echo "FAIL — $1"; fail=$((fail+1)); }

# default_branch <repo-dir> — origin/HEAD if it is set, else main, else master.
default_branch() {
	local r="$1" b
	b=$(git -C "$r" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
	[ -n "$b" ] && { echo "$b"; return; }
	for b in origin/main origin/master main master; do
		git -C "$r" rev-parse --verify --quiet "$b" >/dev/null && { echo "$b"; return; }
	done
	echo ""
}

# repo_holding <sha> — the one repo that resolves it as a commit, or empty.
repo_holding() {
	local sha="$1" r found=""
	for r in . $SUBMODULES; do
		git -C "$r" cat-file -e "${sha}^{commit}" 2>/dev/null && found="$found $r"
	done
	echo "$found" | tr -s ' ' | sed 's/^ //;s/ $//'
}

echo "== C. Submodule pins (superproject $REF)"
for s in $SUBMODULES; do
	pin=$(git rev-parse --verify --quiet "$REF:$s" 2>/dev/null)
	if [ -z "$pin" ]; then
		bad "$s: no submodule entry at $REF"
		continue
	fi
	if [ ! -d "$s/.git" ] && [ ! -f "$s/.git" ]; then
		echo "skip — $s not checked out"
		continue
	fi
	db=$(default_branch "$s")
	[ -n "$db" ] || { bad "$s: cannot determine a default branch"; continue; }
	if ! git -C "$s" cat-file -e "${pin}^{commit}" 2>/dev/null; then
		bad "$s: pinned at $(echo "$pin" | cut -c1-9), which this checkout does not have (fetch?)"
	elif git -C "$s" merge-base --is-ancestor "$pin" "$db"; then
		ok "$s: pin $(echo "$pin" | cut -c1-9) is on $db"
	else
		bad "$s: pin $(echo "$pin" | cut -c1-9) is NOT on $db — shipping an unmerged commit"
	fi
done

echo
echo "== A/B. Commits cited by compliance documents"
cited=$(grep -ohE '`[0-9a-f]{7,40}`' $DOCS 2>/dev/null | tr -d '`' | sort -u)
[ -n "$cited" ] || echo "note — no commit citations found in: $DOCS"

for sha in $cited; do
	holder=$(repo_holding "$sha")
	case "$holder" in
		"")
			echo "note — $sha: no repository resolves this as a commit (typo, unpushed, or not a SHA)"
			continue;;
		*" "*)
			echo "note — $sha: ambiguous, resolves in [$holder] — skipped"
			continue;;
	esac

	subject=$(git -C "$holder" log --format=%s -1 "$sha" 2>/dev/null | cut -c1-56)
	name=$([ "$holder" = "." ] && echo "superproject" || basename "$holder")

	# A — did it land on its own default branch?
	db=$(default_branch "$holder")
	if [ -n "$db" ] && git -C "$holder" merge-base --is-ancestor "$sha" "$db"; then
		ok "$sha ($name): on $db — \"$subject\""
	else
		bad "$sha ($name): NOT on ${db:-its default branch} — \"$subject\""
		continue
	fi

	# B — and does the revision we ship contain it?
	[ "$holder" = "." ] && continue
	pin=$(git rev-parse --verify --quiet "$REF:$holder" 2>/dev/null)
	[ -n "$pin" ] && git -C "$holder" cat-file -e "${pin}^{commit}" 2>/dev/null || continue
	if git -C "$holder" merge-base --is-ancestor "$sha" "$pin"; then
		ok "$sha ($name): included in the pinned revision"
	else
		bad "$sha ($name): merged but NOT in the pinned revision — bump the submodule"
	fi
done

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
