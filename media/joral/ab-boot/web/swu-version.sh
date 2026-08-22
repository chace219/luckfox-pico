#!/bin/sh
# SPDX-License-Identifier: LicenseRef-Joral-Proprietary
# Copyright (c) 2026 Joral LLC. All rights reserved.
# swu-version.sh — the release identity of a platform image, and its ORDER.
#
# One-way door #4 (swupdate-implementation-plan.md, "Item 5"). Until this
# existed the .swu carried `git describe` on an untagged tree — a bare commit
# hash, which has NO ORDER. Nothing could tell whether a package was newer or
# older than what was running, so a *signed* rollback to a known-vulnerable
# release installed silently: the CMS signature is a check on WHO built the
# image, never on WHEN, so signature verification cannot catch a downgrade.
# A v1 unit must still be able to reason about a 2030 image, which is why the
# scheme has to be fixed before the first customer unit ships.
#
# The identity is YYYY.MM.PATCH (e.g. 2026.08.1): date-ordered, so it sorts
# without a release database, and readable as an age at a glance — the thing
# an operator actually needs when deciding whether an advisory applies.
#
# SOURCED, not executed, by three callers, which is the point of putting it
# here rather than inline in any of them:
#   - ./build.sh swu      (host, bash)   — validates what it is about to pack
#   - api-update.sh       (device, ash)  — the console's downgrade gate
#   - ab-boot's `make install`           — stamps /etc/sw-versions into the image
# One comparator, one test suite, and the build and the device can never
# disagree about which of two releases is newer.
#
# POSIX sh only: busybox ash runs it on the device.

# /etc/sw-versions is SWUpdate's own convention (CONFIG_SW_VERSIONS_FILE), one
# "<name> <version>" pair per line. Using it rather than a file of our own keeps
# SWUpdate's built-in version gating available later without a second source of
# truth to drift. It lives on the ROOTFS, deliberately: it must be per-slot, so
# each slot reports the release it actually carries.
#
# Both are overridable so the tests can point them at a scratch file — the same
# path-injection seam the factory-reset script uses, and for the same reason:
# the shipped code must be the tested code.
SW_VERSIONS_FILE=${SW_VERSIONS_FILE:-/etc/sw-versions}
SW_VERSIONS_NAME=${SW_VERSIONS_NAME:-rootfs}

# The phrase an operator types to authorise an install that is not an upgrade.
# Same idiom as the factory reset's RESET, and re-checked server-side for the
# same reason: a control enforced only in the console JavaScript stops nobody
# able to call the CGI directly.
SW_DOWNGRADE_PHRASE=DOWNGRADE

_sw_digits() {
	case "${1:-}" in
		'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

# True if $1 is a well-formed release identity. Everything else in this file
# treats "not valid" as "not orderable", never as "assume it is fine".
sw_version_valid() {
	_v=${1:-}
	_y=${_v%%.*}
	_rest=${_v#*.}
	[ "$_rest" != "$_v" ] || return 1
	_m=${_rest%%.*}
	_p=${_rest#*.}
	[ "$_p" != "$_rest" ] || return 1
	case "$_p" in *.*) return 1 ;; esac   # exactly three fields, not four
	_sw_digits "$_y" && _sw_digits "$_m" && _sw_digits "$_p" || return 1
	[ ${#_y} -eq 4 ] && [ ${#_m} -eq 2 ] || return 1
	[ "$_y" -ge 2000 ] || return 1
	[ "$_m" -ge 1 ] && [ "$_m" -le 12 ] || return 1
	return 0
}

# Order of $2 (candidate) relative to $1 (running): newer | same | older, or
# unknown if either side cannot be ordered.
#
# Field-by-field NUMERIC comparison, never a string compare: 2026.08.10 is
# newer than 2026.08.9, and every lexicographic shortcut gets that backwards.
# The tenth patch of a month is not a rare case — it is where the comparator
# starts mattering.
#
# Always exits 0 and always prints exactly one word. "unknown" is a real answer
# the callers must handle, not an error to be swallowed by `set -e`.
sw_version_order() {
	if ! sw_version_valid "${1:-}" || ! sw_version_valid "${2:-}"; then
		echo unknown
		return 0
	fi
	_ay=${1%%.*}; _ar=${1#*.}; _am=${_ar%%.*}; _ap=${_ar#*.}
	_by=${2%%.*}; _br=${2#*.}; _bm=${_br%%.*}; _bp=${_br#*.}
	for _pair in "$_by:$_ay" "$_bm:$_am" "$_bp:$_ap"; do
		_b=${_pair%%:*}; _a=${_pair#*:}
		# `test -gt` parses DECIMAL in bash, dash and busybox ash, so the
		# zero-padded month ("08", "09") compares as 8 and 9 rather than
		# failing as invalid octal — verified in all three. Arithmetic
		# expansion $(( )) would NOT be safe here for exactly that reason,
		# which is why this comparison is written with test and not $(( )).
		if [ "$_b" -gt "$_a" ]; then echo newer; return 0; fi
		if [ "$_b" -lt "$_a" ]; then echo older; return 0; fi
	done
	echo same
	return 0
}

# True when an install of a package ordered $1 needs explicit operator
# confirmation. "unknown" needs it: an unorderable version is precisely the
# case this gate exists for, so it must never read as safe. Reinstalling the
# same release does not — that is a repair, not a rollback.
sw_version_needs_confirm() {
	case "${1:-}" in
		newer | same) return 1 ;;
		*) return 0 ;;
	esac
}

# The release this running rootfs carries. Empty + non-zero if the file is
# missing, which is what an image built before this scheme looks like — the
# caller must treat that as unorderable rather than as "no downgrade".
sw_version_running() {
	[ -r "$SW_VERSIONS_FILE" ] || return 1
	_out=$(awk -v n="$SW_VERSIONS_NAME" '$1 == n { print $2; exit }' "$SW_VERSIONS_FILE")
	[ -n "$_out" ] || return 1
	printf '%s\n' "$_out"
}

# The release a .swu declares. Reads sw-description straight out of the cpio
# without unpacking the payload beside it — the manifest is the FIRST member,
# so this costs a few kilobytes of a 150 MB file.
#
# The match is anchored at the start of the line: an unanchored `.*version = "`
# would also fire on any other field whose VALUE happened to contain that text,
# and the description field is free-form build provenance.
sw_version_from_swu() {
	[ -r "${1:-}" ] || return 1
	_out=$(cpio -i --to-stdout sw-description < "$1" 2>/dev/null |
		sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' |
		head -n1)
	[ -n "$_out" ] || return 1
	printf '%s\n' "$_out"
}

# Read the tracked release identity out of media/joral/RELEASE_VERSION.
# Tolerates `#` comments and surrounding whitespace so the file can explain
# itself to whoever bumps it.
sw_version_read_file() {
	if [ ! -r "${1:-}" ]; then
		echo "swu-version: cannot read release file ${1:-<unset>}" >&2
		return 1
	fi
	_out=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' | head -n1)
	if [ -z "$_out" ]; then
		echo "swu-version: $1 declares no version" >&2
		return 1
	fi
	printf '%s\n' "$_out"
}

# Stamp the tracked identity ($1) into an image's /etc/sw-versions ($2).
# Called from ab-boot's `make install`, so a malformed RELEASE_VERSION FAILS
# THE BUILD rather than producing an image whose version cannot be ordered —
# which would recreate exactly the defect this file closes. Prints the version.
sw_version_stamp() {
	_v=$(sw_version_read_file "$1") || return 1
	if ! sw_version_valid "$_v"; then
		echo "swu-version: $1 holds '$_v', which is not a YYYY.MM.PATCH release identity" >&2
		return 1
	fi
	mkdir -p "$(dirname "$2")" || return 1
	printf '%s %s\n' "$SW_VERSIONS_NAME" "$_v" > "$2" || return 1
	printf '%s\n' "$_v"
}
