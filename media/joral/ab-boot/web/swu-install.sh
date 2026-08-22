#!/bin/sh
# SPDX-License-Identifier: LicenseRef-Joral-Proprietary
# Copyright (c) 2026 Joral LLC. All rights reserved.
# swu-install.sh — detached A/B install worker for api-update.sh.
#
# The console CGI starts this with setsid and returns at once; the install
# writes ~150 MB to the standby slot and takes a minute or two, far longer
# than a browser holds a request open. This worker owns that long tail:
# it streams SWUpdate's progress to a file the CGI's `progress` action polls,
# marks the slot active on success, and audit-logs the outcome. It writes to
# files only, never to a socket.
#
# Installed beside webauth.sh (same lib dir), so it sources it by $0's dir —
# no path substitution needed. Args:
#   $1 staged .swu   $2 target slot (a|b)   $3 misc device   $4 acting user
#   $5 running version   $6 staged version
#
# $5/$6 exist so the COMPLETION record names the transition, not just the slot.
# It used to log `target=b` alone, which cannot answer "was this unit ever
# running an affected build" — the question an advisory forces, and the one the
# `started` record was written to answer. Half of that was undone by the record
# one line later reporting only a slot. They are passed rather than re-derived
# here so both records are guaranteed to name the same two releases: reading the
# staged package again could disagree with what the gate actually ordered if the
# file changed underneath us, and a pair of audit lines that disagree is worse
# than one that is terse.
set -u

. "$(dirname "$0")/webauth.sh"   # audit_log + its config

STAGED=$1
TARGET=$2
MISC=$3
AUSER=$4
FROM=${5:-unknown}
TO=${6:-unknown}

PCT=/tmp/swu-apply.pct
STATE=/tmp/swu-apply.state
LOG=/tmp/swu-apply.log
PIDF=/tmp/swu-apply.pid
# The CGI holds an flock on fd 9 and we INHERITED that descriptor across
# fork+exec, so the operation stays locked for as long as this worker runs and
# the kernel releases it when we exit, however we exit. Nothing to acquire here
# and nothing to clean up -- which is the point: a lock we managed ourselves
# would need a staleness test, and that cannot be made race-free in shell.
#
# The pid file is only for the progress action; $! and setsid's pid are both
# unreliable for it, so we record our own.
trap 'rm -f "$PIDF"' EXIT INT TERM
echo $$ > "$PIDF"

# Stream SWUpdate's own progress IPC into a single-number file. -w makes the
# reader wait/reconnect until swupdate opens the socket, so start order does
# not matter. Each progress line is "[bar] N of M P% (image), dwl X% of Y" —
# take the per-step "P% (", not the download "X% of".
#
# 9>&- closes the inherited lock descriptor for this pipeline. The flock is
# held by whoever holds the fd, so a progress reader that outlived us -- it
# blocks on a socket and there are three processes to reap -- would keep the
# update locked until the unit rebooted. Only the worker itself should hold it.
# EVERY stage closes fd 9, not just the ends: each is a separate process and
# any one of them still holding the descriptor keeps the flock held. The reader
# blocks on a socket, so it is the likeliest straggler, but a lingering tr or
# awk would lock out updates just as effectively -- until the unit rebooted.
{ swupdate-progress -w 2>/dev/null 9>&- \
  | tr '\r' '\n' 9>&- \
  | awk 'match($0,/[0-9]+% \(/){s=substr($0,RSTART,RLENGTH);gsub(/[^0-9]/,"",s);print s;fflush()}' 9>&- \
  | while IFS= read -r p; do echo "$p" > "$PCT"; done 9>&- ; } 9>&- &
PROG=$!

if swupdate -i "$STAGED" -e "stable,$TARGET" > "$LOG" 2>&1; then
	if misc_ab mark-active "$MISC" "$TARGET"; then
		echo 100 > "$PCT"
		echo "done target=$TARGET" > "$STATE"
		audit_log fw_apply success "$AUSER" \
			"target=$TARGET from=$FROM to=$TO"
	else
		echo "fail could not mark slot active" > "$STATE"
		audit_log fw_apply fail "$AUSER" \
			"target=$TARGET from=$FROM to=$TO reason=mark_active"
	fi
else
	ERR=$({ grep -iE "error|fail" "$LOG" | head -n4; tail -n1 "$LOG"; } | tr '\n' ' ')
	echo "fail $ERR" > "$STATE"
	audit_log fw_apply fail "$AUSER" \
		"target=$TARGET from=$FROM to=$TO reason=install"
fi

kill "$PROG" 2>/dev/null
# pid file and lock are released by the EXIT trap.
