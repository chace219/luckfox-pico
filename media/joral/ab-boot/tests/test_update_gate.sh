#!/bin/sh
# test_update_gate.sh — the downgrade gate in the update CGI (one-way door #4).
#
# Drives the SHIPPED template (web/api-update.sh.in) against a scratch tree via
# SWU_PREFIX, with stubs on PATH for the three things that need real hardware:
# misc_ab, swupdate and the detached install worker. Instantiating the template
# here rather than testing a product copy is deliberate — both products install
# the same file, so a gate proven here is proven on both consoles.
#
# What this guards, worst-first:
#   1. THE GATE IS SERVER-SIDE. Both consoles arm their install button on the
#      same phrase, but that is a screen. If this check regresses, `curl -X POST
#      '...?action=apply'` rolls a unit back to a release a published advisory
#      covers, with a valid signature and no record that anyone chose to.
#   2. "unknown" is refused, not permitted. A unit whose own version cannot be
#      read is exactly the case that must ask, and it is the default state of
#      every image built before the scheme existed.
#   3. Upgrades stay frictionless. A gate that also nags on the normal path
#      trains operators to type the phrase without reading it, which is worse
#      than no gate.
#   4. The audit trail names BOTH versions, on the refusal as well as the
#      install — an advisory names releases, so "slot b" alone cannot answer
#      whether a unit ever ran an affected build.
#   5. A refusal does not touch the device: nothing installed, package still
#      staged for a deliberate retry.
#
# Part of ab-boot's `make test`. Pure POSIX sh, no toolchain needed.
set -u

HERE=$(dirname "$0")
TEMPLATE="$HERE/../web/api-update.sh.in"
VERSION_LIB="$HERE/../web/swu-version.sh"
[ -r "$TEMPLATE" ] || { echo "FAIL: cannot read $TEMPLATE"; exit 1; }

T=$(mktemp -d /tmp/ab_update_gate.XXXXXX) || exit 1
trap 'rm -rf "$T"' EXIT INT TERM

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
want()    { case "$3" in *"$2"*) ok ;; *) bad "$1 — expected to contain '$2', got: $3" ;; esac; }
wantnot() { case "$3" in *"$2"*) bad "$1 — expected NOT to contain '$2', got: $3" ;; *) ok ;; esac; }

mkdir -p "$T/lib" "$T/cgi" "$T/bin" "$T/etc" "$T/tmp" "$T/userdata" "$T/dev" \
         "$T/sys/block/mmcblk0/mmcblk0p7"

# --- stubs -----------------------------------------------------------------
# webauth.sh: only the three things the CGI uses from it. audit_log appends to a
# file so the records themselves can be asserted, which is half the point of the
# gate — a refusal nobody can see afterwards is not a control.
cat > "$T/lib/webauth.sh" <<'EOF'
require_auth() { :; }
current_user() { echo operator; }
audit_log() { printf '%s\n' "$*" >> "$AUDIT"; }
EOF
cp "$VERSION_LIB" "$T/lib/swu-version.sh"

# The partition the CGI discovers by walking sysfs — same method the initramfs
# and the health check use, so the real find_part() runs here.
printf 'PARTNAME=misc\nDEVNAME=mmcblk0p7\n' > "$T/sys/block/mmcblk0/mmcblk0p7/uevent"

# Same one-key-per-line shape misc_ab really prints (src/misc_ab.c), because
# the CGI parses it with anchored sed expressions.
cat > "$T/bin/misc_ab" <<'EOF'
#!/bin/sh
if [ "$1" = status ]; then
	echo "slot_a: priority=15 tries_remaining=7 successful_boot=1"
	echo "slot_b: priority=14 tries_remaining=7 successful_boot=0"
	echo "last_boot=a"
	echo "choice=a"
fi
exit 0
EOF
cat > "$T/bin/swupdate" <<'EOF'
#!/bin/sh
exit 0
EOF
# Stands in for the detached installer: records that an install was actually
# launched, which is how "refused" is distinguished from "silently did nothing".
cat > "$T/lib/swu-install.sh" <<'EOF'
#!/bin/sh
printf 'installed staged=%s target=%s user=%s\n' "$1" "$2" "$4" > "$MARKER"
EOF
chmod +x "$T/bin/misc_ab" "$T/bin/swupdate" "$T/lib/swu-install.sh"

sed "s|@WEBAUTH@|$T/lib/webauth.sh|" "$TEMPLATE" > "$T/cgi/api-update.sh"
chmod +x "$T/cgi/api-update.sh"

AUDIT="$T/audit.log"
MARKER="$T/installed"
export AUDIT MARKER
PATH="$T/bin:$PATH"; export PATH

# --- harness ---------------------------------------------------------------
mkswu() { # mkswu <version>
	d="$T/pkg"; rm -rf "$d"; mkdir -p "$d"
	printf 'software = {\n\tversion = "%s";\n\tdescription = "test";\n};\n' "$1" > "$d/sw-description"
	: > "$d/rootfs.img"
	( cd "$d" && printf 'sw-description\nrootfs.img\n' |
		{ cpio -o -H crc --quiet 2>/dev/null || cpio -o -H newc --quiet 2>/dev/null; } ) \
		> "$T/userdata/update.swu"
	rm -rf "$d"
}

run() { # run <action> [extra query]  -> JSON body on stdout
	rm -f "$AUDIT" "$MARKER"
	SWU_PREFIX="$T" QUERY_STRING="action=$1${2:+&$2}" REQUEST_METHOD=POST \
		sh "$T/cgi/api-update.sh" 2>/dev/null | tr -d '\r' | tail -n1
}

# An install is detached with setsid, so give the worker a moment to land.
installed() {
	i=0
	while [ $i -lt 40 ]; do
		[ -f "$MARKER" ] && return 0
		i=$((i + 1)); sleep 0.05
	done
	return 1
}

set_running() { printf 'rootfs %s\n' "$1" > "$T/etc/sw-versions"; }

echo "== status reports the ordering =="
set_running 2026.08.5
mkswu 2026.09.1
OUT=$(run status)
want "status names the running release" '"running_version":"2026.08.5"' "$OUT"
want "status names the staged release"  '"version":"2026.09.1"'        "$OUT"
want "an upgrade is ordered newer"      '"order":"newer"'              "$OUT"
want "an upgrade needs no confirmation" '"downgrade":false'            "$OUT"

mkswu 2026.08.2
OUT=$(run status)
want "a rollback is ordered older"      '"order":"older"'   "$OUT"
want "a rollback is flagged"            '"downgrade":true'  "$OUT"

mkswu 2026.08.5
OUT=$(run status)
want "a reinstall is ordered same"      '"order":"same"'    "$OUT"
want "a reinstall is not a downgrade"   '"downgrade":false' "$OUT"

# The double-digit trap, end to end and not just in the comparator: 2026.08.10
# over 2026.08.9 is an UPGRADE, and a string compare would flag it as a
# downgrade — training operators to type the phrase on a routine update.
set_running 2026.08.9
mkswu 2026.08.10
OUT=$(run status)
want "patch 10 over 9 is an upgrade"    '"order":"newer"'   "$OUT"
want "patch 10 over 9 asks nothing"     '"downgrade":false' "$OUT"

echo "== upgrades stay frictionless =="
set_running 2026.08.5
mkswu 2026.09.1
OUT=$(run apply)
want "an upgrade starts without a phrase" '"started":true' "$OUT"
if installed; then ok; else bad "an upgrade actually launched the installer"; fi
want "the audit names the transition" "from=2026.08.5 to=2026.09.1" "$(cat "$AUDIT")"
want "the audit marks it not a downgrade" "downgrade=false" "$(cat "$AUDIT")"

mkswu 2026.08.5
OUT=$(run apply)
want "a reinstall starts without a phrase" '"started":true' "$OUT"

echo "== rollbacks are refused without the phrase =="
mkswu 2026.08.2
OUT=$(run apply)
want    "refused with a machine-readable code" '"code":"confirm_required"' "$OUT"
want    "the refusal names both releases"      '"running":"2026.08.5","staged":"2026.08.2"' "$OUT"
wantnot "nothing was started"                  '"started":true' "$OUT"
if installed; then bad "a refused apply must not launch the installer"; else ok; fi
[ -f "$T/userdata/update.swu" ] && ok || bad "a refusal must leave the package staged for a deliberate retry"
want "the refusal is audited with a reason" "reason=downgrade_unconfirmed" "$(cat "$AUDIT")"
want "the refusal audit names both releases" "from=2026.08.5 to=2026.08.2" "$(cat "$AUDIT")"

echo "== only the exact phrase opens it =="
for phrase in downgrade Downgrade yes true 1 DOWNGRADED '' DOWNGRADE_; do
	OUT=$(run apply "confirm=$phrase")
	case "$OUT" in
		*'"code":"confirm_required"'*) ok ;;
		*) bad "phrase '$phrase' must not authorise a rollback: $OUT" ;;
	esac
done

OUT=$(run apply "confirm=DOWNGRADE")
want "the exact phrase authorises it" '"started":true' "$OUT"
if installed; then ok; else bad "a confirmed rollback must launch the installer"; fi
want "a confirmed rollback is audited as one" "downgrade=true" "$(cat "$AUDIT")"
want "and names the transition"               "from=2026.08.5 to=2026.08.2" "$(cat "$AUDIT")"

echo "== unorderable state refuses by default =="
# A unit built before the scheme has no /etc/sw-versions. It must ASK, not
# assume: this is the state every already-built image is in, so a gate that
# defaults open here is a gate that does nothing on the units that have it.
rm -f "$T/etc/sw-versions"
mkswu 2026.08.2
OUT=$(run apply)
want "no running version -> refused" '"code":"confirm_required"' "$OUT"
want "and reported as unorderable"   '"order":"unknown"'         "$OUT"
if installed; then bad "an unorderable apply must not launch the installer"; else ok; fi
OUT=$(run apply "confirm=DOWNGRADE")
want "the phrase still overrides it" '"started":true' "$OUT"

# The mirror image: a package with no orderable version, on a unit that has one.
set_running 2026.08.5
mkswu v1.0.0-66-g2d4b29958
OUT=$(run apply)
want "an unorderable PACKAGE is refused too" '"code":"confirm_required"' "$OUT"
want "and reported as unorderable"           '"order":"unknown"'         "$OUT"

echo "== status survives a missing release file =="
rm -f "$T/etc/sw-versions"
rm -f "$T/userdata/update.swu"
OUT=$(run status)
want "status still answers"            '"ok":true'             "$OUT"
want "with an empty running version"   '"running_version":""'  "$OUT"
want "and no staged package"           '"staged":{"present":false}' "$OUT"

echo "== the gate is evaluated UNDER the operation lock =="
# The staged package is a shared mutable path: upload renames onto it and the
# install worker opens it by name later. If apply classifies the package before
# taking the lock, a concurrent authenticated upload can swap it in between --
# installing a signed OLDER release under a confirmation granted for a newer
# one, and auditing the wrong transition. Found in review (Greptile) on
# satisense-edge#54 / t1s-media-gateway#30.
#
# A race is not deterministically observable from a shell test, but the
# ORDERING that closes it is: hold the lock, then ask apply to install a
# package that would otherwise be refused. If the gate runs before the lock,
# apply answers about the package (confirm_required). If it runs after, apply
# cannot get the lock and says so. The second is the fixed behaviour.
set_running 2026.08.5
mkswu 2026.08.2
rm -f "$AUDIT" "$MARKER"
# Hold the lock from outside, exactly as a concurrent upload or install would.
( flock 9
  OUT=$(SWU_PREFIX="$T" QUERY_STRING="action=apply" REQUEST_METHOD=POST \
        sh "$T/cgi/api-update.sh" 2>/dev/null | tr -d '\r' | tail -n1)
  printf '%s' "$OUT" > "$T/locked-out.json"
) 9>>"$T/tmp/swu-op.lock"
OUT=$(cat "$T/locked-out.json")
wantnot "a held lock is not answered from a stale classification" '"code":"confirm_required"' "$OUT"
want    "a held lock reports the operation in progress" 'already in progress' "$OUT"
if installed; then bad "nothing may install while the lock is held"; else ok; fi

# And with the lock free the gate still refuses -- the fix must not have simply
# disabled it.
OUT=$(run apply)
want "gate still refuses once the lock is free" '"code":"confirm_required"' "$OUT"

echo "== the product copies are the template =="
# Everything above tests the TEMPLATE. Each product tree carries an
# instantiated copy, regenerated by hand — so a gate proven here still ships
# only if those copies were refreshed. That is the whole failure mode this
# section exists for: a stale copy is silently a console without the gate, and
# nothing else in either tree would notice.
# Skipped, not failed, when a sibling product tree is absent (ab-boot builds
# standalone).
check_copy() { # check_copy <label> <cgi path> <lib path> <webauth path>
	if [ ! -f "$2" ]; then
		echo "  skip: $1 not present"
		return
	fi
	if diff -q "$HERE/../web/swu-version.sh" "$3" >/dev/null 2>&1; then ok
	else bad "$1 swu-version.sh differs from ab-boot/web/swu-version.sh"; fi
	if diff -q "$(sed "s|@WEBAUTH@|$4|g" "$TEMPLATE" > "$T/expect.sh"; echo "$T/expect.sh")" \
		"$2" >/dev/null 2>&1; then ok
	else bad "$1 api-update.sh is stale — regenerate it from web/api-update.sh.in"; fi
}
P="$HERE/../.."
check_copy "satisense-edge" \
	"$P/satisense-edge/web/cgi/api-update.sh" \
	"$P/satisense-edge/web/cgi-lib/swu-version.sh" \
	/usr/lib/intelligence-edge/webauth.sh
check_copy "media-gateway" \
	"$P/media-gateway/src/web/cgi/api-update.sh" \
	"$P/media-gateway/src/web/cgi-lib/swu-version.sh" \
	/usr/lib/media-gateway/webauth.sh

echo
echo "update-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
