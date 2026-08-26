#!/bin/bash
# Guard the public disclosure channel (CRA Annex I Part II §5 and §6).
#
# The published-channel duty itself lands 11 Dec 2027 with the rest of Annex I.
# What makes this urgent earlier is Art. 14: from 11 Sep 2026 we owe ENISA and a
# CSIRT a report within 24 h of *becoming aware* that a vulnerability is being
# exploited, and the way we become aware is that a reporter reaches us. The route
# they will try is /.well-known/security.txt. Three ways that route breaks quietly:
#
#   1. EXPIRY. RFC 9116 makes `Expires` mandatory and a lapsed file INVALID.
#      Nothing announces it. A file published once and forgotten stops being a
#      disclosure channel on a date nobody has in a calendar, so this check
#      fails 60 days early — while a renewal is still a chore rather than an
#      incident.
#   2. DRIFT. The address exists in six places: this file, each product's
#      SECURITY.md, each user manual, and the on-device Help generated from
#      those manuals. A researcher who finds two different addresses has to
#      guess, and a unit in the field carries whichever one it shipped with.
#      So the check is agreement across all of them, not the presence of a
#      plausible address in any one.
#   3. PROMISES WE CANNOT KEEP. An `Encryption:` line pointing at a key nobody
#      holds, or a `Policy:` URL that 404s, is worse than the omission — the
#      reporter concludes there is no channel and stops. Optional fields are
#      therefore checked for being *deliberate*, and the file documents why
#      each omitted one is omitted.
#
# Usage: test-security-txt.sh [--live]
#   --live also fetches the published URLs, so it can only run with outbound
#          access and only after publication. Without it the check is purely
#          local and runs on any checkout.
#
# This does NOT assert the mailbox exists — no local check can. That remains
# the open half of the row (cra-compliance-plan.md, remaining-work item 1), and
# it is product management's, not engineering's.
set -u
cd "$(dirname "$0")/../.." || exit 2

TXT=media/joral/disclosure/security.txt
POLICY_MD=media/joral/disclosure/security-policy.md
WARN_DAYS=60

# Every shipped surface that names the address. Drift between any two is the
# defect this catches.
SURFACES="
media/joral/media-gateway/SECURITY.md
media/joral/satisense-edge/SECURITY.md
media/joral/media-gateway/docs/manual/user-manual.md
media/joral/satisense-edge/docs/manual/user-manual.md
media/joral/media-gateway/src/web/www/docs/user-manual.html
media/joral/satisense-edge/web/public/docs/user-manual.html
"

pass=0; fail=0
ok()   { echo "ok   — $1"; pass=$((pass+1)); }
bad()  { echo "FAIL — $1"; fail=$((fail+1)); }

[ -f "$TXT" ] || { echo "FAIL — $TXT missing"; exit 1; }

# field <name> — values of a field, comments and CRs stripped.
field() {
	sed 's/\r$//' "$TXT" | grep -iE "^$1:" | sed -E "s/^[^:]+:[[:space:]]*//"
}

echo "== RFC 9116 required fields"

contacts=$(field Contact)
if [ -z "$contacts" ]; then
	bad "no Contact field (RFC 9116 requires at least one)"
else
	ok "Contact present ($(echo "$contacts" | wc -l) value(s))"
fi

expires=$(field Expires)
n_exp=$(printf '%s' "$expires" | grep -c . || true)
if [ "$n_exp" -ne 1 ]; then
	bad "Expires appears $n_exp times — RFC 9116 requires exactly one"
else
	if ! exp_epoch=$(date -u -d "$expires" +%s 2>/dev/null); then
		bad "Expires is not a parseable RFC 3339 timestamp: \"$expires\""
	else
		now=$(date -u +%s)
		days=$(( (exp_epoch - now) / 86400 ))
		if [ "$days" -lt 0 ]; then
			bad "Expires passed ${days#-} days ago — the file is INVALID under RFC 9116, re-issue it"
		elif [ "$days" -lt "$WARN_DAYS" ]; then
			bad "Expires in $days days (under the $WARN_DAYS-day renewal margin) — re-issue now"
		else
			ok "Expires in $days days ($expires)"
		fi
		# RFC 9116 recommends a validity period under a year.
		[ "$days" -gt 400 ] && bad "Expires is more than ~13 months out; RFC 9116 recommends under a year"
	fi
fi

echo
echo "== Field hygiene"

# Unknown field names are ignored by consumers, which makes a typo invisible.
known="acknowledgments|canonical|contact|csaf|encryption|expires|hiring|policy|preferred-languages"
unknown=$(sed 's/\r$//' "$TXT" | grep -E "^[A-Za-z-]+:" | sed -E "s/:.*//" \
	| tr 'A-Z' 'a-z' | sort -u | grep -vE "^($known)$" || true)
if [ -n "$unknown" ]; then
	bad "unknown field name(s), likely a typo a consumer would silently ignore: $(echo "$unknown" | tr '\n' ' ')"
else
	ok "no unknown field names"
fi

n_lang=$(field Preferred-Languages | grep -c . || true)
if [ "$n_lang" -gt 1 ]; then
	bad "Preferred-Languages appears $n_lang times — RFC 9116 allows at most one"
else
	ok "Preferred-Languages appears at most once"
fi

# Every URI must be https (mailto: excepted); a http:// contact route is one a
# network attacker can silently intercept or drop.
insecure=$(sed 's/\r$//' "$TXT" | grep -E "^[A-Za-z-]+:" | grep -oE "http://[^ ]+" || true)
if [ -n "$insecure" ]; then
	bad "plaintext http:// URI in a field: $(echo "$insecure" | tr '\n' ' ')"
else
	ok "all field URIs are https or mailto"
fi

# Promises we cannot keep are worse than omissions.
for f in Encryption Acknowledgments; do
	v=$(field "$f")
	[ -z "$v" ] && continue
	bad "$f: $v — present, so the target must exist and be monitored; remove it unless it does"
done
ok "no optional field promises a target that does not exist (Encryption/Acknowledgments absent by design)"

echo
echo "== The address agrees everywhere it is published"

addr=$(printf '%s\n' "$contacts" | grep -iE '^mailto:' | head -1 | sed -E 's/^[Mm][Aa][Ii][Ll][Tt][Oo]://')
if [ -z "$addr" ]; then
	bad "no mailto: Contact — a researcher's first move is email"
else
	ok "email contact: $addr"
	for s in $SURFACES; do
		if [ ! -f "$s" ]; then
			echo "note — $s not present in this checkout, skipped"
			continue
		fi
		if grep -qF "$addr" "$s"; then
			ok "${s#media/joral/}: names $addr"
		else
			bad "$s does NOT name $addr — a unit in the field would carry a different address"
		fi
	done
	# And the published policy page must name the same one.
	if [ -f "$POLICY_MD" ] && grep -qF "$addr" "$POLICY_MD"; then
		ok "$(basename "$POLICY_MD"): names $addr"
	else
		bad "$POLICY_MD does not name $addr"
	fi
fi

echo
echo "== Policy URL"
policy=$(field Policy)
if [ -z "$policy" ]; then
	echo "note — no Policy field. Allowed by RFC 9116, but the policy exists, so point at it."
else
	ok "Policy: $policy"
	[ -f "$POLICY_MD" ] && ok "a source document for it is in the tree ($POLICY_MD)" \
		|| bad "Policy names a URL but $POLICY_MD is missing — nothing in the tree produces that page"
fi

if [ "${1:-}" = "--live" ]; then
	echo
	echo "== Published (--live)"
	canon=$(field Canonical | head -1)
	for u in "$canon" "$policy"; do
		[ -z "$u" ] && continue
		code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$u" 2>/dev/null || echo 000)
		[ "$code" = "200" ] && ok "$u -> 200" || bad "$u -> HTTP $code (a reporter following this gets nothing)"
	done
fi

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
