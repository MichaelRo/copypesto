#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SSH orchestrator for Mac B during iCloud Drive sync latency benchmarks (scripts/sync-latency/README.md).
# Drives remote power/eviction conditions on Mac B over SSH:
#   - `lowpower <on|off>`: toggles `pmset -a lowpowermode`
#   - `sleep-wake <seconds>`: schedules `pmset schedule wake` + puts Mac B to sleep via `pmset sleepnow`
#   - `evict <path>`: triggers `fileproviderctl evict` on a synced iCloud Drive file/folder to force dataless placeholders
#
# Usage: scripts/sync-latency/run-remote.sh <ssh-host> <lowpower on|lowpower off|sleep-wake <sec>|evict <path>>
set -euo pipefail

HOST="${1:-}"
ACTION="${2:-}"
ARG="${3:-}"

if [ -z "$HOST" ] || [ -z "$ACTION" ]; then
  echo "usage: scripts/sync-latency/run-remote.sh <ssh-host> <lowpower on|lowpower off|sleep-wake <sec>|evict <path>>" >&2
  exit 2
fi

case "$ACTION" in
  lowpower)
    case "$ARG" in
      on)  VAL=1 ;;
      off) VAL=0 ;;
      *)   echo "error: lowpower requires 'on' or 'off'" >&2; exit 2 ;;
    esac
    ssh "$HOST" "sudo -n pmset -a lowpowermode $VAL"
    echo "ok    [$HOST] lowpowermode=$VAL"
    ;;
  sleep-wake)
    SECS="${ARG:-600}"
    ssh "$HOST" "WAKE=\$(date -v+${SECS}S '+%m/%d/%Y %H:%M:%S') && sudo -n pmset schedule wake \"\$WAKE\" && sudo -n pmset sleepnow"
    echo "ok    [$HOST] sleepnow with wake in ${SECS}s"
    ;;
  evict)
    [ -n "$ARG" ] || { echo "error: evict requires a remote path" >&2; exit 2; }
    ssh "$HOST" "fileproviderctl evict $(printf '%q' "$ARG")"
    echo "ok    [$HOST] evicted $ARG"
    ;;
  *)
    echo "error: unknown action '$ACTION'" >&2
    exit 2
    ;;
esac
