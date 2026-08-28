#!/bin/sh
# can-routes-apply.sh — install kernel CAN gateway rules from can-routes.conf.
#
# Single source of truth for CAN routing, invoked by the boot init script
# (S99canroutes) and by hand after editing the config. Translates operator-facing
# PGN numbers into the id/mask filters cangw expects, so nobody has to hand-build
# 29-bit J1939 identifiers.
#
# J1939 29-bit ID layout:
#   bits 28..26 priority | 25 EDP | 24 DP | 23..16 PF | 15..8 PS | 7..0 SA
# A PGN is (EDP<<17 | DP<<16 | PF<<8 | PS), where for PDU1 (PF < 0xF0) the PS
# byte is the destination address and is NOT part of the PGN — it is zeroed in
# the PGN and must therefore be masked off when matching.
#
# Matching always ignores priority and source address: a PGN should pass from
# any ECU at any priority. That is what makes this a PGN filter rather than a
# CAN-ID filter.

CONF="${CAN_ROUTES_CONF:-/userdata/media-gateway/state/can-routes.conf}"
PGNDB="${J1939_PGN_DB:-/usr/share/media-gateway/j1939-pgns.tsv}"

log() { echo "can-routes: $*"; }

# Resolve a PGN acronym (EEC1, CCVS, ...) to its number via the dictionary.
# Case-insensitive. Echoes nothing if the name is unknown or the file is absent,
# which lets the caller fall through to numeric parsing and report one error.
pgn_lookup() {
	[ -f "$PGNDB" ] || return 1
	awk -F'\t' -v want="$1" '
		BEGIN { want = toupper(want) }
		/^[[:space:]]*#/ || NF < 2 { next }
		toupper($2) == want { print $1; found = 1; exit }
		END { if (!found) exit 1 }
	' "$PGNDB"
}

# Normalise a PGN written as decimal or 0x-hex to a plain decimal number.
# Everything downstream compares decimals: awk's "+0" on "0xFEF2" is 0, which
# would otherwise make every hex PGN collide with PGN 0 in the dictionary.
pgn_norm() {
	awk -v v="$1" 'BEGIN {
		if (v ~ /^0[xX][0-9a-fA-F]+$/) { printf "%d\n", strtonum(v); exit }
		if (v ~ /^[0-9]+$/)            { printf "%d\n", v + 0;      exit }
		exit 1
	}'
}

# Human label for a PGN number, for log lines. Falls back to the bare number.
pgn_label() {
	_d=$(pgn_norm "$1") || { echo "$1"; return; }
	_n=""
	[ -f "$PGNDB" ] && _n=$(awk -F'\t' -v want="$_d" '
		/^[[:space:]]*#/ || NF < 2 { next }
		$1 + 0 == want + 0 { print $2; exit }
	' "$PGNDB")
	if [ -n "$_n" ]; then echo "${_n}(${_d})"; else echo "$_d"; fi
}

# Warn when a PGN is normally carried by J1939 transport protocol: a frame-level
# id/mask filter cannot match those, because they arrive as TP.CM/TP.DT frames
# whose identifiers carry the transport PGN, not the payload PGN. The rule will
# install and simply never match, which is confusing without this warning.
pgn_is_tp() {
	[ -f "$PGNDB" ] || return 1
	_d=$(pgn_norm "$1") || return 1
	_tp=$(awk -F'\t' -v want="$_d" '
		/^[[:space:]]*#/ || NF < 3 { next }
		$1 + 0 == want + 0 { if ($3 ~ /\(TP\)/) print "yes"; exit }
	' "$PGNDB")
	[ "$_tp" = "yes" ]
}

if ! command -v cangw >/dev/null 2>&1; then
	log "cangw not found — cannot install routes"
	exit 1
fi

if [ ! -f "$CONF" ]; then
	log "${CONF} not found — no routes installed"
	exit 0
fi

# PGN -> "value:mask" filter pair for cangw.
# Emits nothing (and returns 1) if the PGN is unparseable or out of range.
pgn_to_filter() {
	awk -v pgn="$1" 'BEGIN {
		# accept decimal or 0x-prefixed hex
		if (pgn ~ /^0[xX][0-9a-fA-F]+$/)      p = strtonum(pgn)
		else if (pgn ~ /^[0-9]+$/)            p = pgn + 0
		else                                  exit 1
		if (p < 0 || p > 0x3FFFF) exit 1

		pf = int(p / 256) % 256

		if (pf < 0xF0) {
			# PDU1: PS is a destination address, not part of the PGN.
			# Match EDP/DP/PF only; ignore PS so the PGN matches whether it
			# was addressed to a specific ECU or broadcast to 0xFF.
			value = int(p / 256) * 256
			mask  = 0x03FF0000
		} else {
			# PDU2: PS is the group extension and IS part of the PGN.
			value = p * 1
			mask  = 0x03FFFF00
		}

		# shift PGN into the PF/PS/DP/EDP field (bits 24..8)
		value = value * 256

		# The CAN_EFF_FLAG (bit 31) is deliberately NOT set here.
		#
		# cangw parses -f with sscanf("%x"), and this image is built against
		# uclibc, whose %x saturates at INT_MAX rather than wrapping. Any value
		# with bit 31 set therefore arrives as 0x7FFFFFFF in BOTH fields, which
		# silently installs a rule matching nothing like the one requested
		# (observed on-device as "-f 5FFFFFFF~7FFFFFFF").
		#
		# Omitting the flag is safe, not merely a workaround: with EFF absent
		# from the mask the kernel matches on identifier bits alone
		# (net/can/af_can.c), and a standard 11-bit frame is masked to 0x7FF
		# before comparison. A PGN filter requires bits in the PF/PS field
		# (>= 0x10000 after the shift), which no SFF frame can ever set, so
		# extended frames alone can match. Verified by construction: for EEC1
		# the required bits are 0x00F00400 while an SFF frame can reach only
		# 0x00000700 under this mask.
		printf "%08X:%08X\n", value, mask
	}'
}

# strip inline comments + whitespace from an INI value
clean() { sed 's/#.*//' | tr -d ' \r\t'; }

# --- flush any previously installed rules -------------------------------
# cangw rules are global kernel state, not owned by this script, so a plain
# flush would also drop rules an operator added by hand. That is the intended
# behaviour: this file is the declared configuration, applied whole.
cangw -F 2>/dev/null || true

rc=0
installed=0

# Walk [route:*] sections. Config files are small; a single awk pass emitting
# one "field=value" line per section keeps this readable in POSIX sh.
sections=$(awk '
	/^[[:space:]]*\[route:/ { insec=1; name=$0; sub(/^[[:space:]]*\[route:/,"",name); sub(/\].*$/,"",name); print "SECTION " name; next }
	/^[[:space:]]*\[/       { insec=0; next }
	insec && /=/            { print }
' "$CONF")

name=""; enabled=""; src=""; dst=""; pgns=""; mode=""

flush_route() {
	[ -n "$name" ] || return 0

	case "$(echo "$enabled" | clean)" in
		false|0|no|"") log "route '${name}': disabled, skipped"; return 0 ;;
	esac

	_src=$(echo "$src" | clean)
	_dst=$(echo "$dst" | clean)
	_mode=$(echo "$mode" | clean)
	_pgns=$(echo "$pgns" | clean)
	[ -n "$_mode" ] || _mode=whitelist

	if [ -z "$_src" ] || [ -z "$_dst" ]; then
		log "route '${name}': src or dst missing, skipped"; rc=1; return 0
	fi
	if [ "$_src" = "$_dst" ]; then
		log "route '${name}': src and dst are both '${_src}', skipped"; rc=1; return 0
	fi
	for i in "$_src" "$_dst"; do
		if [ ! -d "/sys/class/net/$i" ]; then
			log "route '${name}': ${i} not present, skipped"; return 0
		fi
	done

	if [ -z "$_pgns" ]; then
		# Fail closed. An empty whitelist means "pass nothing", which is what
		# the config says; an empty blacklist would mean "pass everything" and
		# is almost certainly a mistake on a chassis tap, so refuse it.
		if [ "$_mode" = "blacklist" ]; then
			log "route '${name}': blacklist with no PGNs would forward the entire bus, skipped"
			rc=1
		else
			log "route '${name}': empty PGN list, nothing forwarded"
		fi
		return 0
	fi

	op=":"
	[ "$_mode" = "blacklist" ] && op="~"

	n=0
	names=""
	OLDIFS=$IFS; IFS=,
	for pgn in $_pgns; do
		IFS=$OLDIFS
		[ -n "$pgn" ] || { IFS=,; continue; }

		# Accept either a dictionary acronym (EEC1) or a number (61444/0xF004).
		# Names are tried first so a hypothetical all-digit acronym could never
		# be silently reinterpreted as a PGN number.
		num=$(pgn_lookup "$pgn" 2>/dev/null) || num="$pgn"

		filt=$(pgn_to_filter "$num")
		if [ -z "$filt" ]; then
			log "route '${name}': unknown PGN name or bad number '${pgn}', skipped"
			rc=1; IFS=,; continue
		fi

		if pgn_is_tp "$num"; then
			log "route '${name}': $(pgn_label "$num") is normally multi-packet (J1939 TP) — a frame filter cannot match it; rule installed but will not fire"
		fi

		val=${filt%%:*}; msk=${filt##*:}
		if cangw -A -s "$_src" -d "$_dst" -f "${val}${op}${msk}" 2>/dev/null; then
			n=$((n + 1))
			names="${names}${names:+, }$(pgn_label "$num")"
		else
			log "route '${name}': cangw rejected PGN ${pgn} (${val}${op}${msk})"; rc=1
		fi
		IFS=,
	done
	IFS=$OLDIFS

	if [ "$n" -gt 0 ]; then
		log "route '${name}': ${_src} -> ${_dst}, ${_mode}: ${names}"
		installed=$((installed + n))
	fi
}

OLDIFS=$IFS
IFS='
'
for line in $sections; do
	case "$line" in
		SECTION\ *)
			flush_route
			name=${line#SECTION }
			enabled=""; src=""; dst=""; pgns=""; mode=""
			;;
		*=*)
			k=${line%%=*}; v=${line#*=}
			k=$(echo "$k" | tr -d ' \t')
			case "$k" in
				enabled) enabled=$v ;;
				src)     src=$v ;;
				dst)     dst=$v ;;
				pgns)    pgns=$v ;;
				mode)    mode=$v ;;
			esac
			;;
	esac
done
IFS=$OLDIFS
flush_route

log "${installed} rule(s) installed"
exit $rc
