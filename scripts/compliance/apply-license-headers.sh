#!/bin/bash
# Apply the Joral outbound licence notice to first-party sources.
#
#  - Files already carrying an SPDX tag have it REPLACED (satisense-edge's 83
#    GPL-2.0+ tags contradict its own LICENSE file and its own SBOM entry).
#  - Files with none get one inserted, after any shebang / "use strict" line.
#  - Third-party, vendored, generated and binary trees are excluded by path.
#
# Usage: apply-license-headers.sh <tree-root>
set -u
ROOT="${1:?usage: apply-license-headers.sh <tree>}"
cd "$ROOT" || exit 2

SPDX="MPL-2.0"
COPY="Copyright (c) 2026 Joral LLC"

changed=0; skipped=0

is_excluded() {
	case "$1" in
		*/node_modules/*|*/dist/*|*/out/*|*/build/*|*/.git/*) return 0;;
		*/web/public/*|*/docs/manual/pdf/*) return 0;;
		*/eipscanner/*|*/third_party/*|*/vendor/*) return 0;;
		*.min.js|*.bundle.js) return 0;;
	esac
	return 1
}

# comment_style <file> -> "line" prefix to use
prefix_for() {
	case "$1" in
		*.c|*.h|*.cpp|*.hpp|*.js|*.jsx|*.mjs|*.css) echo "//";;
		*.sh|*.py|*.cgi|*.mk|Makefile|*/Makefile) echo "#";;
		*) echo "";;
	esac
}

apply() {
	local f="$1" pfx tmp first
	is_excluded "$f" && return
	pfx=$(prefix_for "$f")
	[ -n "$pfx" ] || { skipped=$((skipped+1)); return; }

	# Header files in this codebase use /* ... */ for the tag; keep that.
	local open="$pfx" close=""
	case "$f" in *.h|*.hpp) open="/*"; close=" */";; esac

	tmp=$(mktemp)
	if grep -q "SPDX-License-Identifier" "$f"; then
		# Replace the identifier in place, leave everything else untouched.
		awk -v id="$SPDX" '
			/SPDX-License-Identifier:/ && !done {
				sub(/SPDX-License-Identifier:[ \t]*[^ \t*\/]+/, "SPDX-License-Identifier: " id); done=1
			} { print }' "$f" > "$tmp"
		# Add the copyright line directly under it if the file has none.
		if ! grep -q "Joral LLC" "$f"; then
			awk -v c="$COPY" -v o="$open" -v cl="$close" '
				{ print }
				/SPDX-License-Identifier:/ && !done { print o " " c cl; done=1 }' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
		fi
	else
		first=$(head -1 "$f")
		case "$first" in
			'#!'*)
				{ echo "$first"
				  echo "$pfx SPDX-License-Identifier: $SPDX"
				  echo "$pfx $COPY"
				  tail -n +2 "$f"; } > "$tmp";;
			*)
				{ echo "$open SPDX-License-Identifier: $SPDX$close"
				  echo "$open $COPY$close"
				  cat "$f"; } > "$tmp";;
		esac
	fi

	if cmp -s "$f" "$tmp"; then rm -f "$tmp"; skipped=$((skipped+1)); return; fi
	cat "$tmp" > "$f"; rm -f "$tmp"
	changed=$((changed+1))
}

while IFS= read -r f; do apply "$f"; done < <(
	find . \( -path ./node_modules -o -path ./.git -o -path ./out -o -path ./web/node_modules -o -path ./web/dist \) -prune -o \
	     -type f \( -name "*.c" -o -name "*.h" -o -name "*.cpp" -o -name "*.hpp" \
	              -o -name "*.sh" -o -name "*.jsx" -o -name "*.js" -o -name "*.mjs" \
	              -o -name "*.py" -o -name "*.cgi" \) -print | sort
)

echo "$changed changed, $skipped unchanged/skipped"
