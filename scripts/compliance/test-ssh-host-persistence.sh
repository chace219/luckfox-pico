#!/bin/bash
# Guard SSH host-key persistence across A/B updates
# (CRA Annex I #1 "secure by default", #3; compliance plan item 15, finding A).
#
# /etc/ssh lives on the rootfs SLOT. Stock `ssh-keygen -A` therefore mints a new
# host identity on the first boot of every update, and each slot keeps its own,
# so identity flips as slots alternate. What that costs is not confidentiality —
# it is the operator, who is shown REMOTE HOST IDENTIFICATION HAS CHANGED by a
# benign event often enough to learn to clear it. A warning that cries wolf on
# every update is worse than no warning.
#
# S50sshd keeps the keys on /userdata and symlinks the default paths at them.
# This drives THAT script — via its `persist-keys` entry point and the
# $SSHD_STATE_ROOT prefix — rather than reimplementing the logic here, so the
# behaviour tested is the behaviour that ships. Same pattern as satisense's
# factory-reset suite.
#
# Usage: test-ssh-host-persistence.sh [rootfs-staging-dir ...]
#   With no argument the tracked overlay script is exercised, so this runs on a
#   clean checkout with no build. Extra arguments are packed/staging rootfs
#   trees, checked only if they exist — the overlay is applied at firmware-pack
#   time, so a staging tree is where "the overlay never reached the image"
#   becomes visible.
set -u
cd "$(dirname "$0")/../.." || exit 2

OVERLAY_SSHD=project/cfg/BoardConfig_IPC/overlay/overlay-luckfox-buildroot-init/etc/init.d/S50sshd

pass=0; fail=0
ok()  { echo "ok   — $1"; pass=$((pass+1)); }
bad() { echo "FAIL — $1"; fail=$((fail+1)); }

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# seed <dir-with-keys> — a plausible pair, contents irrelevant to the logic
seed() { mkdir -p "$1"; echo "PRIVATE" > "$1/ssh_host_ed25519_key"; echo "PUBLIC" > "$1/ssh_host_ed25519_key.pub"; }

run_persist() { SSHD_STATE_ROOT="$1" sh "$OVERLAY_SSHD" persist-keys >/dev/null 2>&1; }

[ -f "$OVERLAY_SSHD" ] || { echo "FAIL — $OVERLAY_SSHD missing"; exit 1; }

echo "== Case A — a slot that already has keys hands them to /userdata"
# This is the upgrade path: the running unit's identity must be adopted, not
# replaced, or the change would itself cause the warning it exists to prevent.
A="$TMP/a"; mkdir -p "$A/userdata"; seed "$A/etc/ssh"
run_persist "$A"
if [ -f "$A/userdata/platform/ssh/ssh_host_ed25519_key" ] && \
   [ "$(cat "$A/userdata/platform/ssh/ssh_host_ed25519_key")" = PRIVATE ]; then
	ok "A: the existing key moved to /userdata with its contents intact"
else
	bad "A: the existing key did not reach /userdata"
fi
if [ -L "$A/etc/ssh/ssh_host_ed25519_key" ]; then
	ok "A: /etc/ssh now holds a symlink, not a copy"
else
	bad "A: /etc/ssh/ssh_host_ed25519_key is not a symlink — a copy on the slot defeats the whole change"
fi
# The link must be absolute and slot-independent: a relative or prefixed target
# would resolve inside the test tree and break on the device.
if [ "$(readlink "$A/etc/ssh/ssh_host_ed25519_key")" = /userdata/platform/ssh/ssh_host_ed25519_key ]; then
	ok "A: the symlink target is the absolute on-device path"
else
	bad "A: symlink target is '$(readlink "$A/etc/ssh/ssh_host_ed25519_key")', not the on-device path"
fi
m=$(stat -c '%a' "$A/userdata/platform/ssh/ssh_host_ed25519_key")
[ "$m" = 600 ] && ok "A: private key is 0600 (sshd stats through the symlink and refuses looser)" \
                || bad "A: private key is $m — sshd will refuse to load it"
d=$(stat -c '%a' "$A/userdata/platform/ssh")
[ "$d" = 700 ] && ok "A: the persistent directory is 0700" || bad "A: persistent dir is $d"

echo "== Case B — a fresh slot restores the identity from /userdata"
# The point of the exercise: an updated rootfs has no keys at all, and must
# come up as the SAME host it was before the update.
B="$TMP/b"; mkdir -p "$B/etc/ssh"; seed "$B/userdata/platform/ssh"
run_persist "$B"
# Assert the LINK, not its contents: the target is the absolute on-device path,
# which by design does not resolve inside a prefixed test tree. Following it
# here would test the harness, not the unit.
if [ -L "$B/etc/ssh/ssh_host_ed25519_key" ] && \
   [ "$(readlink "$B/etc/ssh/ssh_host_ed25519_key")" = /userdata/platform/ssh/ssh_host_ed25519_key ]; then
	ok "B: a keyless slot links to the persisted identity"
else
	bad "B: a keyless slot did not pick up the persisted key — every update would change identity"
fi
# ...and the persisted key must be untouched by the restore.
if [ "$(cat "$B/userdata/platform/ssh/ssh_host_ed25519_key")" = PRIVATE ]; then
	ok "B: the persisted key is left intact"
else
	bad "B: the restore modified the persisted key"
fi

echo "== Case C — an unmounted /userdata must not look like success"
# The mountpoint directory exists on the rootfs whether or not S20linkmount
# worked. Writing keys into it would persist them onto the slot again while
# reporting success, which is the failure this check exists for. Production
# gates on /proc/mounts; the test asserts the gate is present and gates on the
# real thing rather than on directory existence.
if grep -q "grep -q ' /userdata ' /proc/mounts" "$OVERLAY_SSHD"; then
	ok "C: persistence is gated on /userdata being a real mount"
else
	bad "C: no /proc/mounts check — an unmounted /userdata would silently persist onto the slot"
fi
if grep -q 'logger -t sshd' "$OVERLAY_SSHD"; then
	ok "C: the degraded case is reported to syslog rather than passing quietly"
else
	bad "C: the unmounted case is silent"
fi

echo "== Ordering — restore must happen before ssh-keygen -A, and again after"
# -A decides what to generate by testing the default paths. Restoring after it
# would mean -A had already minted a new identity; not restoring afterwards
# would leave anything it DID create on the slot.
# CODE lines only. This file's own header explains the design and quotes both
# `ssh-keygen -A` and the function name, and matching prose would order the
# comments rather than the script — the identical mistake the getty check in
# test-root-credential.sh made and had corrected.
code() { grep -nE "^[^#]*$1" "$OVERLAY_SSHD" | grep -v '()' ; }
before=$(code 'persist_host_keys' | head -1 | cut -d: -f1)
keygen=$(code 'ssh-keygen -A'     | head -1 | cut -d: -f1)
after=$(code 'persist_host_keys'  | tail -1 | cut -d: -f1)
if [ -n "$before" ] && [ -n "$keygen" ] && [ "$before" -lt "$keygen" ]; then
	ok "restore runs before ssh-keygen -A"
else
	bad "ssh-keygen -A runs before the restore — it would mint a new identity every update"
fi
if [ -n "$after" ] && [ -n "$keygen" ] && [ "$after" -gt "$keygen" ]; then
	ok "a second persist runs after ssh-keygen -A"
else
	bad "nothing persists what ssh-keygen -A creates — a newly supported key type would live on the slot"
fi

if [ $# -gt 0 ]; then
	echo "== Staging / packed trees"
	for tree in "$@"; do
		[ -d "$tree" ] || { echo "skip — $tree not built"; continue; }
		t="$tree/etc/init.d/S50sshd"
		if [ ! -f "$t" ]; then
			bad "$(basename "$tree"): no S50sshd"
		elif cmp -s "$t" "$OVERLAY_SSHD"; then
			ok "$(basename "$tree"): S50sshd matches the overlay"
		else
			bad "$(basename "$tree"): S50sshd differs from the overlay — the packed image is not what this file guards"
		fi
	done
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
