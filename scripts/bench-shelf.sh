#!/bin/bash
# SPDX-License-Identifier: MIT
# Measures what one arrow press, a held arrow and a collection switch cost the shelf, on histories shaped like real ones
# (`imported`: what a Paste import leaves; `mixed`; `large`). The app drives itself through the same code a key press
# runs (UI-test commands `benchArrowSteps`, `benchArrowHold`, `benchCycleCollections`), so no Accessibility grant and no
# synthetic key events are needed, but the Mac must be unlocked and awake: a locked screen draws no frames. Link previews
# stay ON and are answered by a local stub after a fixed wait (`PESTO_UITEST_LINK_STUB_MS`), so no request leaves the Mac.
#
#   scripts/bench-shelf.sh [label]            # SEEDS="imported mixed" to choose histories, JSON=1 to keep summaries
#
# PROFILE=1 also records a Time Profiler trace of one drive (PROFILE_DRIVE, default benchCycleCollections) and prints
# where the main thread spent its time (`profile-scroll/top_frames.py`).
#
# Prints, per history and drive: commit time per step (p50, p95, max) and how many view bodies ran per step.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
LABEL=${1:-$(git rev-parse --abbrev-ref HEAD | tr '/' '-')}
IDENTITY="Pesto Development"
OUT=$(mktemp -d)
HERE="$(cd "$(dirname "$0")" && pwd)"

if pgrep -x Pesto > /dev/null; then echo "bench-shelf: a Pesto is running; quit it first (two at once spoil each other)" >&2; exit 1; fi

make generate > /dev/null
xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
  -derivedDataPath .build/xcode-profile CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > "$OUT/build.log" 2>&1
APP="$OUT/Pesto.app"
ditto .build/xcode-profile/Build/Products/Profile/Pesto.app "$APP"
rm -rf "$APP"/Contents/PlugIns/*.xctest "$APP"/Contents/PlugIns/*.xctest.dSYM
codesign -f -s "$IDENTITY" --entitlements Sources/Controls/PestoControls.entitlements \
  "$APP/Contents/PlugIns/PestoControls.appex" > /dev/null 2>&1
codesign -f -s "$IDENTITY" --entitlements Sources/Resources/Pesto.entitlements "$APP" > /dev/null 2>&1

enqueue() { # <work dir> <command>
  printf '%s' "$2" > "$1/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"
}

FAILED=0
for seed in ${SEEDS:-imported mixed large}; do
  W="$OUT/pesto-work-$LABEL-$seed"
  mkdir -p "$W/commands"
  PESTO_UITEST_SESSION="shelf-$LABEL-$seed" PESTO_UITEST_DIR="$W" PESTO_UITEST_SEED="$seed" \
    PESTO_UITEST_ACCESSIBILITY=trusted PESTO_UITEST_DEFAULT_hasOnboarded=true \
    PESTO_UITEST_DEFAULT_linkPreviewsEnabled=true PESTO_UITEST_LINK_STUB_MS="${LINK_STUB_MS:-250}" \
    PESTO_UITEST_PERF_TIMELINE=1 "$APP/Contents/MacOS/Pesto" -UITestMode > "$OUT/$seed.app.log" 2>&1 &
  PID=$!
  trap 'kill $PID 2>/dev/null || true' EXIT
  for _ in $(seq 1 900); do [ -f "$W/ready.json" ] && break; sleep 1; done
  [ -f "$W/ready.json" ] || { echo "== $seed: the app never became ready" >&2; FAILED=1; kill $PID 2>/dev/null || true; continue; }
  enqueue "$W" showOverlay
  sleep 4
  for drive in benchArrowSteps benchArrowHold benchCycleCollections benchCycleHold; do
    rm -f "$W/bench-done"
    START=$(wc -l < "$W/perf-timeline.tsv" 2>/dev/null || echo 0)
    TRACE=""
    if [ -n "${PROFILE:-}" ] && [ "$drive" = "${PROFILE_DRIVE:-benchCycleCollections}" ]; then
      TRACE="$OUT/$LABEL-$seed-$drive.trace"
      xcrun xctrace record --template 'Time Profiler' --attach "$PID" --time-limit "${PROFILE_SECONDS:-30}s" \
        --output "$TRACE" --no-prompt < /dev/null > "$OUT/$seed-$drive.xctrace.log" 2>&1 &
      TRACE_PID=$!
      sleep 5
    fi
    enqueue "$W" "$drive"
    for _ in $(seq 1 120); do [ -f "$W/bench-done" ] && break; sleep 1; done
    [ -f "$W/bench-done" ] || { echo "== $seed/$drive: did not finish in 120 s" >&2; FAILED=1; continue; }
    sleep 1
    if [ -n "$TRACE" ]; then
      wait "$TRACE_PID" || true
      xcrun xctrace export --input "$TRACE" --xpath '/trace-toc/run/data/table[@schema="time-profile"]' \
        < /dev/null > "$OUT/$LABEL-$seed-$drive.tp.xml" 2>/dev/null || true
      echo "-- main-thread profile of $drive"
      python3 "$HERE/profile-scroll/top_frames.py" "$OUT/$LABEL-$seed-$drive.tp.xml" --top "${PROFILE_TOP:-30}" || true
    fi
    tail -n +"$((START + 1))" "$W/perf-timeline.tsv" > "$OUT/$LABEL-$seed-$drive.tsv"
    echo "== $LABEL / $seed / $drive"
    python3 "$HERE/profile-scroll/shelf_report.py" "$OUT/$LABEL-$seed-$drive.tsv" ${JSON:+--json "$OUT/$LABEL-$seed-$drive.json"}
  done
  kill $PID 2>/dev/null || true
  wait $PID 2>/dev/null || true
  rm -rf "$W"
done
echo "logs: $OUT"
exit $FAILED
