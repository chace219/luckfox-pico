#!/bin/bash
# Guard the shipped root credential (CRA Annex I #1 "secure by default", #4).
#
# The Luckfox BSP ships root password "luckfox", which is printed in the
# vendor's own public documentation — so on any unit built from the stock BSP
# it is not a secret at all. It was replaced 2026-08-16. This test exists
# because the replacement is easy to lose silently in three separate ways:
#
#   1. The EFFECTIVE hash is not the one buildroot generates. The board overlay
#      rsyncs its own /etc/shadow over the rootfs AFTER target-finalize, so
#      BR2_TARGET_GENERIC_ROOT_PASSWD is only a fallback. Before 2026-08-16 the
#      two disagreed in both value and strength (overlay $1$ MD5-crypt vs
#      buildroot's $5$) and nothing noticed.
#   2. Buildroot never uninstalls, and a repack ships whatever is already in a
#      staging tree — the failure mode that kept mpv, iperf and the wifi_app
#      binaries alive after they were deselected.
#   3. Re-hashing the SAME vendor word with a fresh salt looks like a change in
#      a diff. So the check recomputes the vendor password against each file's
#      own salt rather than comparing against a known hash string.
#
# Usage: test-root-credential.sh [rootfs-staging-dir ...]
#   With no argument the tracked sources are checked (the overlay + both
#   defconfigs). Any extra arguments are packed/staging rootfs trees, checked
#   only if they exist, so this runs on a clean checkout as well as after a
#   build.
#
# SUPERSEDED 2026-08-19 by a product decision, and the file now guards the
# stronger state: serial console access is not provided on production images,
# so the getty is removed and the root account is LOCKED (`*` in the overlay's
# /etc/shadow, the same value every other system account already carried).
#
# The password's only remaining use had been serial-console recovery — SSH has
# been PermitRootLogin prohibit-password since 2026-08-08, so it was already
# unreachable over the network. Withdrawing the console withdrew the last
# reason to ship a shared secret at all, which retires the three-way product
# decision (shared value / lock / per-unit) in favour of the strongest option
# at no functional cost.
#
# The two halves must stay together, and that is why they are guarded in ONE
# file: a live getty in front of a locked account is a prompt nobody can pass,
# and a removed getty in front of a live shared password leaves a fleet secret
# behind a door that is merely closed. The checks below fail if either half is
# lost. See media/joral/cra-compliance-plan.md remaining-work item 2.
set -u
cd "$(dirname "$0")/../.." || exit 2

OVERLAY=project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-shadow/etc/shadow
DEFCONFIGS="sysdrv/tools/board/buildroot/luckfox_pico_w_defconfig sysdrv/tools/board/buildroot/luckfox_pico_defconfig"
VENDOR_PW=luckfox

pass=0; fail=0
ok()   { echo "ok   — $1"; pass=$((pass+1)); }
bad()  { echo "FAIL — $1"; fail=$((fail+1)); }

command -v openssl >/dev/null || { echo "openssl required"; exit 2; }

# root_hash <shadow-file> -> the crypt field, or empty
root_hash() { awk -F: '$1=="root"{print $2}' "$1" 2>/dev/null; }

check_shadow() {
	local what="$1" file="$2" h salt method recomputed
	[ -f "$file" ] || { bad "$what: $file missing"; return; }
	h=$(root_hash "$file")
	[ -n "$h" ] || { bad "$what: no root entry in $file"; return; }

	# The two conventional "locked" values are NOT interchangeable on this
	# image, and the difference is invisible in the file.
	#
	# openssh 9.3p2 auth.c: allowed_user() calls platform_locked_account()
	# whenever UsePAM is off (it is), and a true answer denies EVERY
	# authentication method — public keys included. platform.c decides that
	# from three optional macros, and this build's config.h defines exactly
	# one: LOCKED_PASSWD_PREFIX "!". LOCKED_PASSWD_STRING and
	# LOCKED_PASSWD_SUBSTR are #undef.
	#
	# So `*` disables password login and leaves key-authenticated root SSH
	# working, while `!` disables key auth too. Since 2026-08-19 the image
	# ships no serial getty, which makes `!` an UNRECOVERABLE lockout: no
	# console, no key, reflash only. Verified against
	# output/build/openssh-9.3p2/{auth.c,platform.c,config.h} on 2026-08-19.
	case "$h" in
		'*')
			ok "$what: root password disabled with '*' (key auth still permitted)"
			return;;
		'!'*)
			bad "$what: root is '!'-locked — openssh platform_locked_account() would refuse PUBKEY auth too, and with no getty this unit would be reachable only by reflash. Use '*'."
			return;;
	esac

	method=$(echo "$h" | cut -d'$' -f2)
	salt=$(echo "$h" | cut -d'$' -f3)
	case "$method" in
		5|6) ok "$what: SHA-crypt (\$$method\$)";;
		1)   bad "$what: MD5-crypt (\$1\$) — busybox is built with USE_BB_CRYPT_SHA, use \$6\$";;
		*)   bad "$what: DES or unknown crypt method (\"$h\")";;
	esac

	# The load-bearing one: is this the vendor password under a new salt?
	recomputed=$(openssl passwd "-$method" -salt "$salt" "$VENDOR_PW" 2>/dev/null)
	if [ -n "$recomputed" ] && [ "$recomputed" = "$h" ]; then
		bad "$what: root password is still the published vendor default \"$VENDOR_PW\""
	else
		ok "$what: not the published vendor default"
	fi
}

echo "== Tracked sources"
check_shadow "board overlay (EFFECTIVE — rsynced over the rootfs last)" "$OVERLAY"

for dc in $DEFCONFIGS; do
	[ -f "$dc" ] || { bad "defconfig $dc missing"; continue; }
	val=$(grep -E '^BR2_TARGET_GENERIC_ROOT_PASSWD=' "$dc" | cut -d'"' -f2)
	if [ "$val" = "$VENDOR_PW" ]; then
		bad "$(basename "$dc"): BR2_TARGET_GENERIC_ROOT_PASSWD is still \"$VENDOR_PW\""
	else
		ok "$(basename "$dc"): fallback password is not the vendor default"
	fi
	m=$(grep -E '^BR2_TARGET_GENERIC_PASSWD_METHOD=' "$dc" | cut -d'"' -f2)
	case "$m" in
		sha-512|sha-256) ok "$(basename "$dc"): passwd method $m";;
		"")              bad "$(basename "$dc"): no BR2_TARGET_GENERIC_PASSWD_METHOD (buildroot would pick its default)";;
		*)               bad "$(basename "$dc"): passwd method \"$m\" is weaker than sha-256";;
	esac
done

echo "== The mode has to be narrowed by the build, and only the build can do it"
# /etc/shadow shipped 0755 in every image ever built until 2026-08-19 —
# world-readable and executable, carrying the hash this file spends its length
# protecting. Three mechanisms each look like the place to fix it and none of
# them can:
#
#   - git stores only the executable bit, so a 0600 file in the tree checks out
#     0644 for the next person;
#   - RK_POST_BUILD_SCRIPT runs BEFORE post_overlay, so the overlay overwrites
#     whatever it sets;
#   - post_overlay installs with `rsync --chmod=u=rwX,go=rX`, which CANNOT
#     express a mode narrower than 0644. Every overlay file is world-readable
#     by construction.
#
# So the guarantee is one hook in build_firmware, immediately after
# post_overlay, and this checks that it is still there and still after it.
if ! grep -q '__HARDEN_SECRET_FILE_MODES' build.sh; then
	bad "build.sh no longer hardens overlay-installed modes; /etc/shadow will ship world-readable"
elif [ "$(grep -n 'post_overlay$' build.sh | tail -1 | cut -d: -f1)" -lt \
       "$(grep -n '^\s*__HARDEN_SECRET_FILE_MODES$' build.sh | tail -1 | cut -d: -f1)" ]; then
	ok "build.sh narrows overlay-installed modes after post_overlay"
else
	bad "__HARDEN_SECRET_FILE_MODES runs before post_overlay, which would then undo it"
fi

echo "== The serial getty must be removed by the build"
# Buildroot's skeleton inittab ships `console::respawn:/sbin/getty ...`, and
# neither a defconfig nor an overlay can express its removal — the skeleton is
# installed by buildroot itself, after both. The one place that can is the
# post-build hook, so this checks the hook still does it AND that a packed tree
# actually came out without it. Checking only the hook would pass on an image
# repacked from a stale staging tree, which is the failure mode that kept mpv
# and the wifi_app binaries alive after they were deselected.
HOOK=project/cfg/BoardConfig_IPC/luckfox-hardening-post.sh
if [ ! -f "$HOOK" ]; then
	bad "post-build hardening hook $HOOK is missing"
else
	grep -q 'remove_serial_getty()' "$HOOK" \
		&& ok "hook defines remove_serial_getty()" \
		|| bad "hook no longer defines remove_serial_getty()"
	# Defined but never called is the silent regression this catches: the
	# function body can look perfect while nothing invokes it.
	grep -qE '^remove_serial_getty$' "$HOOK" \
		&& ok "hook invokes remove_serial_getty" \
		|| bad "remove_serial_getty is defined but never invoked"
fi

echo "== Customer-facing documentation must not print it"
# The value is deliberately not published: manuals, quick-starts and the
# on-device Help are what a customer receives. The compliance fact sheets are
# technical-file documents and are allowed to state it.
docleak=0
for d in media/joral/*/docs/manual media/joral/*/web/public/docs; do
	[ -d "$d" ] || continue
	hits=$(grep -rlniE 'root (password|pw)[^.]{0,40}(joral|luckfox)' "$d" 2>/dev/null)
	[ -n "$hits" ] && { bad "root password appears in customer docs: $hits"; docleak=1; }
done
[ $docleak -eq 0 ] && ok "no customer-facing document prints the root password"

if [ $# -gt 0 ]; then
	echo "== Staging / packed trees"
	for tree in "$@"; do
		[ -d "$tree" ] || { echo "skip — $tree not built"; continue; }
		check_shadow "$(basename "$tree")" "$tree/etc/shadow"
		# Modes survive packing unchanged — mkfs.ext4 -d copies them verbatim,
		# and the ownership pass in mkfs_ext4.sh only ever touches uid/gid — so
		# the staging tree is a faithful reading of what the image ships.
		if [ -f "$tree/etc/shadow" ]; then
			mode=$(stat -c '%a' "$tree/etc/shadow")
			case "$mode" in
				600|400|0600|0400) ok "$(basename "$tree"): /etc/shadow is $mode";;
				*) bad "$(basename "$tree"): /etc/shadow is $mode — readable beyond root";;
			esac
		fi
		# The getty half, read from what actually shipped. An inittab with
		# no getty line is the whole assertion: the kernel still logs to the
		# console via the cmdline, but nothing offers a login on it.
		# An ACTIVE directive, not the word: the skeleton carries an
		# explanatory comment ("# Put a getty on the serial port") beside the
		# line, and matching that would report a finding against a file whose
		# only trace of a getty is prose.
		if [ -f "$tree/etc/inittab" ]; then
			live=$(grep -vE '^[[:space:]]*#' "$tree/etc/inittab" | grep -m1 getty)
			if [ -n "$live" ]; then
				bad "$(basename "$tree"): /etc/inittab still serves a getty — $live"
			else
				ok "$(basename "$tree"): no active getty in /etc/inittab"
			fi
		else
			bad "$(basename "$tree"): /etc/inittab missing"
		fi
		# The packed tree must agree with the overlay, since the overlay is
		# what a firmware repack applies last.
		if [ -f "$tree/etc/shadow" ] && [ "$(root_hash "$tree/etc/shadow")" = "$(root_hash "$OVERLAY")" ]; then
			ok "$(basename "$tree"): matches the board overlay"
		else
			echo "note — $(basename "$tree") differs from the overlay (fine for buildroot's own target/, which the overlay replaces at pack time)"
		fi
	done
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
