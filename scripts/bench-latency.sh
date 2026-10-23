#!/bin/bash
# SPDX-License-Identifier: MIT
# Measures paste and copy latency per kind of clip end to end, with a real target app and the real clipboard.
#
#   scripts/bench-latency.sh [paste|copy|open|hover|memory|both|all] [runs-per-kind]     (default: both = paste and copy, 7)
#
# Builds a signed Profile copy of Pesto (Release, plus the test hooks), seeds an isolated history, and runs a small target
# app (scripts/bench-latency/BenchTarget.swift) that presses ⌘1 to ⌘8 for the paste bench and writes one clip of each kind
# to the clipboard for the copy bench. Pesto writes its stage timings to perf-timeline.tsv; analyze.py joins both.
# The clipboard is saved first and put back at the end, even on Ctrl-C. Needs: Pesto quit, the Mac unlocked, awake and
# left alone for about five minutes, and Accessibility for the app that runs this script (it posts key events).
set -euo pipefail
cd "$(dirname "$0")/.."
FAILED=0
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
MODE=${1:-both}
RUNS=${2:-7}
IDENTITY="Pesto Development"
OUT=.build/perf/latency-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
pgrep -x Pesto >/dev/null && { echo "bench-latency: quit Pesto first" >&2; exit 1; }

make generate >/dev/null
xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
  -derivedDataPath .build/xcode-profile CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
  || { tail -20 "$OUT/build.log" >&2; exit 1; }
APP="$OUT/Pesto.app"
ditto .build/xcode-profile/Build/Products/Profile/Pesto.app "$APP"
rm -rf "$APP"/Contents/PlugIns/*.xctest "$APP"/Contents/PlugIns/*.xctest.dSYM
codesign -f -s "$IDENTITY" --entitlements Sources/Controls/PestoControls.entitlements "$APP/Contents/PlugIns/PestoControls.appex" >/dev/null 2>&1
codesign -f -s "$IDENTITY" --entitlements Sources/Resources/Pesto.entitlements "$APP" >/dev/null 2>&1
# LaunchServices applies Info.plist's LSEnvironment (MallocLargeCache=0); starting the binary directly does not, so this
# script applies it itself and refuses to measure an app that does not carry it (P-02).
BUNDLE_ENV=$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$APP/Contents/Info.plist" | sed -n 's/^ *\(.*\) = \(.*\)$/\1=\2/p' | tr '\n' ' ')
swiftc -O -o "$OUT/BenchTarget" scripts/bench-latency/BenchTarget.swift

run_scenario() {
  local scenario=$1 seed=$2
  local work="$OUT/pesto-latency-$scenario"
  mkdir -p "$work/commands"
  PESTO_UITEST_SESSION="latency-$scenario" PESTO_UITEST_DIR="$work" PESTO_UITEST_SEED="$seed" \
    PESTO_UITEST_REAL_PASTE=1 PESTO_UITEST_ACCESSIBILITY=trusted PESTO_UITEST_DEFAULT_hasOnboarded=true \
    PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false env ${BENCH_PESTO_ENV:-$BUNDLE_ENV} "$APP/Contents/MacOS/Pesto" -UITestMode >"$work/app.log" 2>&1 &
  local pid=$!
  trap 'kill $pid 2>/dev/null || true' RETURN
  for _ in $(seq 1 300); do [ -f "$work/ready.json" ] && break; sleep 1; done
  [ -f "$work/ready.json" ] || { echo "bench-latency: Pesto never became ready ($work/app.log)" >&2; return 1; }
  sleep 3
  if [ -n "$BUNDLE_ENV" ] && [ -z "${BENCH_PESTO_ENV:-}" ] && ! ps eww -p "$pid" | grep -q "MallocLargeCache=0"; then
    echo "bench-latency: the app runs without the environment its Info.plist sets (MallocLargeCache=0)" >&2
    return 1
  fi
  echo "bench-latency: app environment: ${BENCH_PESTO_ENV:-$BUNDLE_ENV}"
  if [ "$scenario" = memory ]; then
    memory_line() { vmmap -summary "$pid" 2>/dev/null | grep -E "^Physical footprint" | tr -s ' ' | tr '\n' ' '; echo; }
    sleep 10
    echo "memory before the long copies: $(memory_line)" | tee "$OUT/$scenario.txt"
    "$OUT/BenchTarget" "$scenario" "$work" "$RUNS"
    sleep 5
    echo "memory right after:            $(memory_line)" | tee -a "$OUT/$scenario.txt"
    sleep 40
    echo "memory 40 s later:             $(memory_line)" | tee -a "$OUT/$scenario.txt"
    vmmap -summary "$pid" >"$OUT/memory-regions.txt" 2>&1 || true
    heap "$pid" >"$OUT/memory-heap.txt" 2>&1 || true
  else
    "$OUT/BenchTarget" "$scenario" "$work" "$RUNS"
    python3 scripts/bench-latency/analyze.py "$scenario" "$work" | tee "$OUT/$scenario.txt" || FAILED=1
  fi
  kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true
}

{ echo "machine: $(sysctl -n hw.model) / $(sw_vers -productVersion) / load $(uptime | sed 's/.*load averages*: //')"; } | tee "$OUT/env.txt"
case "$MODE" in
  paste) run_scenario paste latency ;;
  copy) run_scenario copy large ;;
  open) run_scenario open large ;;
  hover) run_scenario hover latency ;;
  memory) run_scenario memory large ;;
  both) run_scenario paste latency; run_scenario copy large ;;
  all) run_scenario paste latency; run_scenario copy large; run_scenario open large; run_scenario hover latency ;;
  *) echo "bench-latency: unknown mode $MODE" >&2; exit 2 ;;
esac
echo "results: $OUT"
exit $FAILED
