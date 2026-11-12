#!/bin/bash
# SPDX-License-Identifier: MIT
# Measures the FIRST shelf open of a launch, which is the slow one (330 ms in docs/perf/budgets-2026-10.md against a 100 ms
# budget), with and without the pre-warm (`ShelfPrewarm`), launches interleaved so the Mac's own noise cancels. Each launch
# seeds a history, waits for the pre-warm window, opens the shelf once and reads the show-to-commit time and the footprint.
#
#   scripts/bench-first-open.sh [launches-per-variant] [seed]       # default 4, imported; the Mac must be unlocked
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
N=${1:-4}
SEED=${2:-imported}
IDENTITY="Pesto Development"
OUT=$(mktemp -d)
pgrep -x Pesto >/dev/null && { echo "bench-first-open: quit Pesto first" >&2; exit 1; }
make generate >/dev/null
xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
  -derivedDataPath .build/xcode-profile CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1
APP="$OUT/Pesto.app"
ditto .build/xcode-profile/Build/Products/Profile/Pesto.app "$APP"
rm -rf "$APP"/Contents/PlugIns/*.xctest "$APP"/Contents/PlugIns/*.xctest.dSYM
codesign -f -s "$IDENTITY" --entitlements Sources/Controls/PestoControls.entitlements "$APP/Contents/PlugIns/PestoControls.appex" >/dev/null 2>&1
codesign -f -s "$IDENTITY" --entitlements Sources/Resources/Pesto.entitlements "$APP" >/dev/null 2>&1

enqueue() { printf '%s' "$2" > "$1/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"; }
footprint() { vmmap -summary "$1" 2>/dev/null | grep -E "^Physical footprint:" | head -1 | tr -s ' ' | cut -d' ' -f3; }

for run in $(seq 1 "$N"); do
  for variant in cold warm; do
    W="$OUT/pesto-work-$variant-$run"; mkdir -p "$W/commands"
    PREWARM_OFF=""; [ "$variant" = cold ] && PREWARM_OFF=1
    PESTO_NO_PREWARM=$PREWARM_OFF PESTO_UITEST_SESSION="first-$variant-$run" PESTO_UITEST_DIR="$W" PESTO_UITEST_SEED="$SEED" \
      PESTO_UITEST_ACCESSIBILITY=trusted PESTO_UITEST_DEFAULT_hasOnboarded=true PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
      PESTO_UITEST_PERF_TIMELINE=1 "$APP/Contents/MacOS/Pesto" -UITestMode >"$OUT/$variant-$run.log" 2>&1 &
    PID=$!
    for _ in $(seq 1 300); do [ -f "$W/ready.json" ] && break; sleep 1; done
    sleep 14          # past the pre-warm's 5 s delay and the seeding's own background work
    CLOSED_MB=$(footprint "$PID")
    enqueue "$W" showOverlay
    sleep 6
    OPEN_FOOT=$(footprint "$PID")
    OPEN_MS=$(python3 - "$W/perf-timeline.tsv" <<'PY'
import sys
ms = [(int(r[3]) - int(r[2])) / 1e6 for r in (l.rstrip("\n").split("\t") for l in open(sys.argv[1])) if r[1] == "overlayShow"]
print(f"{ms[0]:.1f}" if ms else "none")
PY
)
    PRE=$(grep -c "prewarmDone" "$W/perf-timeline.tsv" || true)
    echo "$variant run $run: first open $OPEN_MS ms, footprint closed $CLOSED_MB MB, after the open $OPEN_FOOT MB, prewarm finished: $PRE"
    echo "$variant $OPEN_MS" >> "$OUT/results.txt"
    kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true; rm -rf "$W"
  done
done
BUDGET_MS=${BUDGET_MS:-120}   # the pre-warmed first open; the budget in AGENTS.md is 100 ms on a developer Mac, with headroom for noise
python3 - "$OUT/results.txt" "$BUDGET_MS" <<'PY'
import statistics, sys
by = {}
for line in open(sys.argv[1]):
    name, value = line.split()
    if value != "none":
        by.setdefault(name, []).append(float(value))
status = 0
for name, values in by.items():
    median = statistics.median(values)
    print(f"== {name}: first open median {median:.1f} ms (min {min(values):.1f}, max {max(values):.1f}, n={len(values)})")
    if name == "warm" and median > float(sys.argv[2]):
        print(f"bench-first-open: the pre-warmed first open is over {sys.argv[2]} ms")
        status = 1
sys.exit(status)
PY
