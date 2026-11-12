#!/bin/bash
# SPDX-License-Identifier: MIT
# How smoothly a trackpad-like scroll runs, without a profiler (`xctrace` hangs finalizing an Animation Hitches trace on some runs):
# the gaps between the shelf's scroll updates are the frames it produced (`scroll_cadence.py`). Needs the Mac unlocked and Accessibility for the terminal (the scroll is posted as real events).
#
#   scripts/bench-scroll-cadence.sh [launches-per-variant] [seed]        # default 3, imported
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
N=${1:-3}; SEED=${2:-imported}
OUT=$(mktemp -d); HERE="$(cd "$(dirname "$0")" && pwd)"
pgrep -x Pesto >/dev/null && { echo "bench-scroll-cadence: quit Pesto first" >&2; exit 1; }
make generate >/dev/null
xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
  -derivedDataPath .build/xcode-profile CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1
APP="$OUT/Pesto.app"; ditto .build/xcode-profile/Build/Products/Profile/Pesto.app "$APP"
rm -rf "$APP"/Contents/PlugIns/*.xctest "$APP"/Contents/PlugIns/*.xctest.dSYM
codesign -f -s "Pesto Development" --entitlements Sources/Controls/PestoControls.entitlements "$APP/Contents/PlugIns/PestoControls.appex" >/dev/null 2>&1
codesign -f -s "Pesto Development" --entitlements Sources/Resources/Pesto.entitlements "$APP" >/dev/null 2>&1
swiftc -O "$HERE/profile-scroll/scroll.swift" -o "$OUT/scroll"
enqueue() { printf '%s' "$2" > "$1/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"; }
for run in $(seq 1 "$N"); do
  for variant in run; do
    W="$OUT/pesto-work-$variant-$run"; mkdir -p "$W/commands"
    PESTO_UITEST_SESSION="cad-$variant-$run" PESTO_UITEST_DIR="$W" PESTO_UITEST_SEED="$SEED" \
      PESTO_UITEST_ACCESSIBILITY=trusted PESTO_UITEST_DEFAULT_hasOnboarded=true PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
      PESTO_UITEST_PERF_TIMELINE=1 "$APP/Contents/MacOS/Pesto" -UITestMode >"$OUT/$variant-$run.log" 2>&1 &
    PID=$!
    for _ in $(seq 1 300); do [ -f "$W/ready.json" ] && break; sleep 1; done
    enqueue "$W" showOverlay; sleep 8
    "$OUT/scroll" 4 >/dev/null; sleep 1
    echo "$variant run $run: $(python3 "$HERE/profile-scroll/scroll_cadence.py" "$W/perf-timeline.tsv")"
    kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true; rm -rf "$W"
  done
done
