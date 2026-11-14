#!/bin/zsh
# SPDX-License-Identifier: MIT
# Runs `swift test` and stops it when the log has been silent too long, then names the tests that never finished.
# A stuck run prints nothing and exits never (text recognition once blocked every Swift thread for hours), so a run
# started by an agent or left unattended goes through here.
#
# usage: scripts/swift-test-watched.sh <log file> <silent seconds> [swift test arguments…]
set -u
if (( $# < 2 )); then
  echo "usage: $0 <log file> <silent seconds> [swift test arguments…]" >&2
  exit 64
fi
log=$1; stall=$2; shift 2
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
mkdir -p "$(dirname "$log")"
: > "$log"
swift test "$@" >> "$log" 2>&1 &
pid=$!
verdict=finished
while kill -0 $pid 2>/dev/null; do
  sleep 15
  idle=$(( $(date +%s) - $(stat -f %m "$log") ))
  if (( idle > stall )); then
    verdict="STALLED: no output for ${idle}s"
    pkill -P $pid 2>/dev/null
    pkill -f swiftpm-testing-helper 2>/dev/null
    kill $pid 2>/dev/null
    break
  fi
done
wait $pid 2>/dev/null; code=$?
echo "== $verdict (exit $code) =="
grep -E "Test run with|Executed [0-9]+ tests" "$log" | tail -3
echo "passed $(grep -c '^✔ Test' "$log"), failed $(grep -c '^✘ Test "' "$log")"
grep -E "recorded an issue|error:" -A2 "$log" | grep -v "CoreData: error" | cut -c1-260 | head -30
if [[ $verdict != finished ]]; then
  echo "-- started but never finished:"
  comm -23 <(grep '^◇ Test' "$log" | sed 's/^◇ Test //; s/ started\.$//' | sort) \
           <(grep -E '^(✔|✘) Test "' "$log" | sed -E 's/^(✔|✘) Test //; s/ (passed|failed) after.*$//' | sort) | head -25
  exit 124
fi
exit $code
