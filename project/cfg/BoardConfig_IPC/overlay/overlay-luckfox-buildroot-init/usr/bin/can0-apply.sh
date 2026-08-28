#!/bin/sh
# can0-apply.sh — bring up a CAN link from the [can_bus] settings in an INI file.
#
# Despite the name this now drives EITHER channel, selected by $CAN_IFACE and
# $GATEWAY_CONF (kept as-is because the web UI privop and existing docs call it
# by this path):
#   can0 -> /userdata/media-gateway/state/gateway.conf  (default; web UI copy)
#   can1 -> /userdata/media-gateway/state/can1.conf     (S98can1config)
#
# Single source of truth for the CAN link config, invoked by:
#   - the boot init scripts (S98can0config, S98can1config)
#   - the web UI CGI (config.sh) on "Save & Apply"  [can0 only]
# so boot-time and runtime use the same path. This is what makes a runtime
# CAN 2.0B <-> CAN FD transition from the configuration page take effect on the
# bus (the media-gateway daemon itself only opens an already-up can0 — ADR-016).
#
# Reads the [can_bus] section of $GATEWAY_CONF:
#   can_fd, can_arb_bitrate, can_data_bitrate,
#   can_arb_sample_point, can_data_sample_point   (sample points are percent)
# Falls back to classic 500 kbit/s if the file/keys are absent.

# Interface and config file are both overridable so this one script serves
# BOTH channels: can0 from gateway.conf (owned by the web UI), can1 from
# can1.conf (owned by the operator over SSH — the config page's CGI rewrites
# gateway.conf wholesale, so can1 must not live there).
IFACE="${CAN_IFACE:-can0}"
# The STATE copy on /userdata, not /etc: the config moved there in Phase 0 of
# the swupdate plan (operator settings must survive an A/B rootfs update), but
# this default kept pointing at the abandoned /etc location — so the [can_bus]
# settings the console saved were never applied to the link at boot or on
# Save & Apply; the script silently fell back to classic 500 kbit/s defaults.
# Observed on the bench 2026-08-28 as can0 up with sample-point 0.875 (the
# kernel default) while gateway.conf said 80.
CONF="${GATEWAY_CONF:-/userdata/media-gateway/state/gateway.conf}"
RESTART_MS="${CAN_RESTART_MS:-100}"

log() { echo "${IFACE}-apply: $*"; }

# read an INI value: strip inline "# comment" and whitespace
ini() {
	grep -E "^[[:space:]]*$1=" "$CONF" 2>/dev/null | head -1 \
		| cut -d= -f2- | sed 's/#.*//' | tr -d ' \r'
}

# percent (e.g. 80) -> kernel fraction (0.800); empty if unset/zero
pct2frac() {
	[ -n "$1" ] || return 0
	awk -v v="$1" 'BEGIN{ if (v+0 > 0) printf "%.3f", v/100 }' 2>/dev/null
}

if [ ! -d "/sys/class/net/${IFACE}" ]; then
	log "${IFACE} not present (mcp251xfd not bound / SPI fault?)"
	exit 1
fi

FD=$(ini can_fd)
ABR=$(ini can_arb_bitrate);          ABR="${ABR:-500000}"
DBR=$(ini can_data_bitrate);         DBR="${DBR:-2000000}"
ASP=$(pct2frac "$(ini can_arb_sample_point)")
DSP=$(pct2frac "$(ini can_data_sample_point)")

set -- "$IFACE" type can bitrate "$ABR"
[ -n "$ASP" ] && set -- "$@" sample-point "$ASP"
case "$FD" in
	true|1|yes)
		set -- "$@" dbitrate "$DBR"
		[ -n "$DSP" ] && set -- "$@" dsample-point "$DSP"
		set -- "$@" fd on
		MODE="CAN FD ${ABR}/${DBR}"
		;;
	*)
		set -- "$@" fd off
		MODE="classic ${ABR}"
		;;
esac
set -- "$@" restart-ms "$RESTART_MS"

# Reconfigure (link must be DOWN to change bittiming)
ip link set "$IFACE" down 2>/dev/null

if ! ip link set "$@"; then
	log "failed to configure ${IFACE} (${MODE})"
	exit 1
fi
if ! ip link set "$IFACE" up; then
	log "failed to bring up ${IFACE}"
	exit 1
fi

log "${IFACE} up — ${MODE} (restart-ms ${RESTART_MS})"
exit 0
