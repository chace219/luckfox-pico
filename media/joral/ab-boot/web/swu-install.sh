#!/bin/sh
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
set -u

. "$(dirname "$0")/webauth.sh"   # audit_log + its config

STAGED=$1
TARGET=$2
MISC=$3
AUSER=$4

PCT=/tmp/swu-apply.pct
STATE=/tmp/swu-apply.state
LOG=/tmp/swu-apply.log
PIDF=/tmp/swu-apply.pid

# WE own the pid file, not the caller: the CGI launches us through setsid,
# whose $! is setsid's own pid and may be gone the moment it forks — the
# progress poll then reports "nothing running" while the install is in fact
# still writing the slot.
echo $$ > "$PIDF"

# Stream SWUpdate's own progress IPC into a single-number file. -w makes the
# reader wait/reconnect until swupdate opens the socket, so start order does
# not matter. Each progress line is "[bar] N of M P% (image), dwl X% of Y" —
# take the per-step "P% (", not the download "X% of".
swupdate-progress -w 2>/dev/null | tr '\r' '\n' \
  | awk 'match($0,/[0-9]+% \(/){s=substr($0,RSTART,RLENGTH);gsub(/[^0-9]/,"",s);print s;fflush()}' \
  | while IFS= read -r p; do echo "$p" > "$PCT"; done &
PROG=$!

if swupdate -i "$STAGED" -e "stable,$TARGET" > "$LOG" 2>&1; then
	if misc_ab mark-active "$MISC" "$TARGET"; then
		echo 100 > "$PCT"
		echo "done target=$TARGET" > "$STATE"
		audit_log fw_apply success "$AUSER" "target=$TARGET"
	else
		echo "fail could not mark slot active" > "$STATE"
		audit_log fw_apply fail "$AUSER" "target=$TARGET reason=mark_active"
	fi
else
	ERR=$({ grep -iE "error|fail" "$LOG" | head -n4; tail -n1 "$LOG"; } | tr '\n' ' ')
	echo "fail $ERR" > "$STATE"
	audit_log fw_apply fail "$AUSER" "target=$TARGET reason=install"
fi

kill "$PROG" 2>/dev/null
rm -f "$PIDF"
