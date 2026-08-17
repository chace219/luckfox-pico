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
# NOT a strength claim: "joral" is a short word and the hash is offline-
# crackable in seconds by anyone holding the image. The control that matters is
# that the value is unreachable over the network (SSH key-only, no telnet,
# default-deny firewall); this password exists for serial-console recovery, and
# a per-unit password is still the open product decision. See
# media/joral/cra-compliance-plan.md remaining-work item 2.
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

	# Locked/absent credential is acceptable and needs no further checks.
	case "$h" in
		'*'|'!'*) ok "$what: root login is locked ($h)"; return;;
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
