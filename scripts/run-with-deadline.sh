#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs a command and gives up on it after a number of seconds: the command and everything it started are stopped and
# the script exits 124 (the status of `timeout`, which macOS does not ship). Otherwise it exits with the command's own
# status.
#
#   scripts/run-with-deadline.sh <seconds> <command> [arguments...]
set -u
LIMIT=${1:?seconds}; shift
[ "$#" -gt 0 ] || { echo "run-with-deadline: no command" >&2; exit 2; }
FIRED=$(mktemp)
rm -f "$FIRED"

# Job control gives the command its own process group, so one signal reaches the whole tree (xctrace starts helpers).
set -m
"$@" &
COMMAND=$!
(
  sleep "$LIMIT"
  : > "$FIRED"
  echo "run-with-deadline: gave up on '$1' after ${LIMIT}s" >&2
  kill -TERM -- "-$COMMAND" 2>/dev/null
  sleep 5
  kill -KILL -- "-$COMMAND" 2>/dev/null
) &
WATCHDOG=$!

wait "$COMMAND"
STATUS=$?
if [ -e "$FIRED" ]; then
  rm -f "$FIRED"
  exit 124
fi
kill -- "-$WATCHDOG" 2>/dev/null || kill "$WATCHDOG" 2>/dev/null
wait "$WATCHDOG" 2>/dev/null
exit "$STATUS"
