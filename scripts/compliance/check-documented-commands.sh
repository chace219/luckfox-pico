#!/bin/bash
# Gate: no document tells an operator to run a command this image does not have.
#
# CRA Annex II (accurate facts for the technical file) and Annex I Part II §3 —
# a runbook is a control only if the steps in it execute.
#
# WHY THIS EXISTS. `logread` has never been in this image: BusyBox is built with
# CONFIG_LOGREAD and CONFIG_FEATURE_IPC_SYSLOG unset, so the applet is absent
# and the circular buffer it reads does not exist. syslogd writes a plain file,
# /var/log/messages. That was found on the bench on 2026-08-16, written into
# bench-backlog-runbook.md §6 — including the exact trap, that
# `logread | grep -c` returns 0 when the command is missing and so reads like a
# clean result — and then, on 2026-08-21, the same command was written into four
# new bench legs AND was found sitting in both products' CUSTOMER MANUALS,
# telling operators to run it for TLS diagnosis and watchdog history.
#
# So the fact was known, recorded, and re-broken within five days by the person
# who had read the record. A note in a document is not a control. This is.
#
# HOW IT DECIDES. With a build present it asks the PACKED ROOTFS whether each
# command exists, rather than trusting a list — the same discipline as reading a
# version out of the image instead of the file beside it. Without a build it
# falls back to the small tracked list of commands already proven absent, so the
# gate still runs on a clean checkout.
#
# Usage: check-documented-commands.sh [--verbose]
set -u
cd "$(dirname "$0")/../.." || exit 2

ROOTFS_IMG=${DOC_ROOTFS_IMG:-output/image/rootfs.img}

# Commands the documents actually use on the device. Each is looked up in the
# image; add one here when a document starts using it.
CANDIDATES=(
	logread cat tail head grep dmesg logger netstat ss ip ifconfig lsmod insmod
	rmmod candump cansend cangen ls find du df ps kill reboot sync mount umount
	openssl curl wget stat awk sed misc_ab swupdate-client bridge iptables
	ip6tables start-stop-daemon
)

# Proven absent, for the no-build path. Keep in step with what the image says.
KNOWN_ABSENT=(logread stat)

# TWO CLASSES OF DOCUMENT, because they are read differently.
#
# OPERATOR docs are instructions: a manual or a bench runbook is read WHILE
# holding the unit, and a backticked command in prose is typed as readily as one
# in a code block. Both count.
#
# RECORD docs are history: the compliance plan and the implementation plans
# discuss commands, including ones that do not exist — that discussion is how
# the fact gets passed on, and demanding it be reworded would make the record
# worse to protect nobody. In these, only a FENCED BLOCK is an instruction.
#
# The distinction is the file's role, not its content, so it cannot be gamed by
# moving a sentence.
OPERATOR_DOCS=(
	media/joral/bench-backlog-runbook.md
	README_PLCA_CAN_OPERATIONS.md
	media/joral/satisense-edge/docs/manual/user-manual.md
	media/joral/satisense-edge/docs/manual/quick-start.md
	media/joral/media-gateway/docs/manual/user-manual.md
	media/joral/media-gateway/docs/manual/quick-start.md
	media/joral/media-gateway/docs/manual/installation-firmware.md
)
RECORD_DOCS=(
	media/joral/cra-compliance-plan.md
	media/joral/swupdate-implementation-plan.md
	media/joral/image-ownership-and-ssh-key-plan.md
	media/joral/audit-log-forwarding-plan.md
	media/joral/firmware-signing-and-support-policy.md
)

VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

pass=0; fail=0
ok()   { echo "ok   — $1"; pass=$((pass+1)); }
bad()  { echo "FAIL — $1"; fail=$((fail+1)); }
skip() { echo "skip — $1"; }
note() { [ $VERBOSE -eq 1 ] && echo "       $1"; return 0; }

# in_image <cmd> — is there such an executable anywhere on PATH in the image?
in_image() {
	local c=$1 d
	for d in /bin /sbin /usr/bin /usr/sbin; do
		debugfs -R "stat $d/$c" "$ROOTFS_IMG" 2>/dev/null | grep -q 'Inode:' && return 0
	done
	return 1
}

ABSENT=()
if [ -f "$ROOTFS_IMG" ] && command -v debugfs >/dev/null 2>&1; then
	echo "== Which documented commands exist in the packed image"
	for c in "${CANDIDATES[@]}"; do
		if in_image "$c"; then
			note "present: $c"
		else
			ABSENT+=("$c")
		fi
	done
	ok "asked the image about ${#CANDIDATES[@]} commands; ${#ABSENT[@]} absent: ${ABSENT[*]:-none}"

	# The list in this file must not drift from what the image says, in EITHER
	# direction: a command that comes back is one the docs may use again.
	for k in "${KNOWN_ABSENT[@]}"; do
		found=0
		for a in "${ABSENT[@]:-}"; do [ "$a" = "$k" ] && found=1; done
		if [ $found -eq 0 ] && in_image "$k"; then
			bad "KNOWN_ABSENT lists '$k' but the image has it — update this gate before relying on it"
		fi
	done
else
	skip "no packed rootfs — falling back to the tracked list: ${KNOWN_ABSENT[*]}"
	ABSENT=("${KNOWN_ABSENT[@]}")
fi

echo
echo "== No document tells an operator to run one of them"
# Match COMMAND POSITION, not the word. The first version of this gate matched
# the bare word and flagged `stat` inside `debugfs -R "stat …"` (a host tool
# reading an image) and the prose "an openssl bump" — noise that would have got
# the gate switched off, which is how a check stops being a check.
#
# Command position is: the first word inside a fenced block (after an optional
# "$ " prompt), a word after a pipe or && or ; inside one, or a word straight
# after an opening backtick in prose. Lines naming a host tool that takes a
# subcommand (debugfs) are excluded — what follows there is not a device command.
command_hits() {
	local cmd=$1 prose=$2; shift 2
	awk -v cmd="$cmd" -v prose="$prose" '
		/^[[:space:]]*```/ { fence = !fence; next }
		{
			line = $0
			if (line ~ /debugfs/) next
			hit = 0
			if (fence) {
				probe = line
				sub(/^[[:space:]]*/, "", probe)
				sub(/^\$ +/, "", probe)
				if (probe ~ ("^" cmd "([[:space:]]|$)")) hit = 1
				if (line ~ ("[|;][[:space:]]*" cmd "([[:space:]]|$)")) hit = 1
				if (line ~ ("&&[[:space:]]*" cmd "([[:space:]]|$)")) hit = 1
			}
			if (prose == "1") {
				# An opening backtick straight onto the command, then a space, a
				# pipe, or a closing backtick not glued to more letters —
				# `stat`ed is English, not a call.
				if (line ~ ("`" cmd "([[:space:]|]|$)")) hit = 1
				if (line ~ ("`" cmd "`[^[:alnum:]]")) hit = 1
				if (line ~ ("`" cmd "`$")) hit = 1
			}
			if (hit) printf "%s:%d:%s\n", FILENAME, FNR, $0
		}
	' "$@"
}

for c in "${ABSENT[@]:-}"; do
	hits=$( { command_hits "$c" 1 "${OPERATOR_DOCS[@]}"
	          command_hits "$c" 0 "${RECORD_DOCS[@]}"; } | grep -v 'check-documented-commands' || true)
	if [ -z "$hits" ]; then
		ok "no document invokes '$c'"
		continue
	fi
	# Even in an operator document, a line may legitimately EXPLAIN the absence.
	bare=$(echo "$hits" | grep -viE "no [\`']?${c}|${c}[\`']? (applet|is absent|does not exist|is not (in|available|going))|without .*${c}|CONFIG_LOGREAD|which \*\*this image does not ship" || true)
	if [ -z "$bare" ]; then
		ok "'$c' appears only where its absence is being explained"
	else
		bad "'$c' is not in the image but is invoked as a command in:"
		echo "$bare" | sed 's/^/       /'
	fi
done

echo
echo "== The on-device Help and the PDFs are not stale"
# Fixing a manual is only half the job: the HTML served as on-device Help and
# the customer PDFs are GENERATED from the markdown and committed, so a source
# fixed without a re-render ships the old text to the customer and to the unit.
# That gap was real on 2026-08-21 — 23 `logread` uses were corrected in the
# sources while every unit in the field and every PDF still said it — and
# nothing in the build noticed.
#
# mtime alone CANNOT answer this once the files are committed, and trusting it
# cost a false failure on 2026-08-21: satisense's user-manual.md was reported
# stale against its PDF with the two 2 ms apart, BOTH unmodified, and generated
# by the same commit (869622f). Git does not record mtimes, so a fresh clone or
# a submodule checkout stamps the pair in whatever order it wrote them — this
# check was a coin flip on any clean checkout, and a gate that fails at random
# is a gate people learn to ignore.
#
# So ask git, which knows: when both files are tracked AND clean, the commit
# that last touched each is the ground truth for "was the artifact regenerated
# with its source". Fall back to mtime the moment either side is dirty or
# untracked — for a file someone is editing right now mtime is exactly the
# right signal, and that is the case this gate exists to catch: someone edits
# the markdown and stops.
function generated_is_stale() {   # $1 = source .md, $2 = generated artifact
	local src="$1" gen="$2" repo ts_src ts_gen
	src=$(realpath "$src" 2>/dev/null) || { [ "$1" -nt "$2" ]; return; }
	gen=$(realpath "$gen" 2>/dev/null) || { [ "$1" -nt "$2" ]; return; }
	repo=$(git -C "$(dirname "$src")" rev-parse --show-toplevel 2>/dev/null) \
		|| { [ "$src" -nt "$gen" ]; return; }
	# Dirty or untracked on either side: mtime is meaningful, use it.
	if [ -n "$(git -C "$repo" status --porcelain -- "$src" "$gen" 2>/dev/null)" ] \
	   || ! git -C "$repo" ls-files --error-unmatch -- "$src" >/dev/null 2>&1 \
	   || ! git -C "$repo" ls-files --error-unmatch -- "$gen" >/dev/null 2>&1; then
		[ "$src" -nt "$gen" ]; return
	fi
	ts_src=$(git -C "$repo" log -1 --format=%ct -- "$src" 2>/dev/null)
	ts_gen=$(git -C "$repo" log -1 --format=%ct -- "$gen" 2>/dev/null)
	[ -n "$ts_src" ] && [ -n "$ts_gen" ] || { [ "$src" -nt "$gen" ]; return; }
	[ "$ts_src" -gt "$ts_gen" ]
}
GENERATED=(
	"media/joral/satisense-edge/docs/manual:media/joral/satisense-edge/web/public/docs"
	"media/joral/media-gateway/docs/manual:media/joral/media-gateway/src/web/www/docs"
)
stale=0
for pair in "${GENERATED[@]}"; do
	src=${pair%%:*}; out=${pair##*:}
	[ -d "$src" ] && [ -d "$out" ] || { skip "$src -> $out (not both present)"; continue; }
	for md in "$src"/*.md; do
		[ -f "$md" ] || continue
		base=$(basename "$md" .md)
		html="$out/$base.html"
		[ -f "$html" ] || continue
		if generated_is_stale "$md" "$html"; then
			bad "$base.md is newer than the Help HTML — re-run scripts/render-manual.mjs --pdf"
			stale=1
		fi
		pdf="$src/pdf/$base.pdf"
		if [ -f "$pdf" ] && generated_is_stale "$md" "$pdf"; then
			bad "$base.md is newer than $base.pdf — the customer PDF is stale"
			stale=1
		fi
	done
done
[ $stale -eq 0 ] && ok "every generated Help page and PDF was regenerated with its source"

echo
echo "-- $pass passed, $fail failed"
[ $fail -eq 0 ] || exit 1
