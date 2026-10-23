#!/bin/bash
# SPDX-License-Identifier: MIT
# Records an Animation Hitches trace of the shelf while a trackpad-like scroll runs, and prints the hitch summary.
# Needs the Mac unlocked and awake (a locked screen draws nothing), Accessibility for the terminal (the scroll is posted
# as real events), and a signed Profile app (`-configuration Profile`: Release with test hooks, which a Release build ignores) with the embedded test bundles removed (see `make install` for the steps).
#
#   scripts/profile-scroll.sh <label> <path/to/Pesto.app> [seed]     # seed defaults to "large"; try "marketing"
set -euo pipefail
LABEL=${1:?label}; APP=${2:?app path}; SEED=${3:-large}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${PROFILE_OUT:-$(mktemp -d)}"
W="$OUT/pesto-work-$LABEL"            # the app only accepts a work directory whose name starts with "pesto-"
mkdir -p "$W/commands"
swiftc -O "$HERE/profile-scroll/scroll.swift" -o "$OUT/scroll"

PESTO_UITEST_SESSION="prof-$LABEL" PESTO_UITEST_DIR="$W" PESTO_UITEST_SEED="$SEED" PESTO_UITEST_ACCESSIBILITY=trusted \
  PESTO_UITEST_DEFAULT_hasOnboarded=true PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false PESTO_UITEST_PERF_TIMELINE=1 \
  "$APP/Contents/MacOS/Pesto" -UITestMode > "$OUT/$LABEL.app.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -rf "$W"' EXIT
for _ in $(seq 1 900); do [ -f "$W/ready.json" ] && break; sleep 1; done
[ -f "$W/ready.json" ] || { echo "the app never became ready" >&2; exit 1; }
printf showOverlay > "$W/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"
sleep 6
xcrun xctrace record --template 'Animation Hitches' --attach "$PID" --time-limit 40s --output "$OUT/$LABEL.trace" \
  --no-prompt > "$OUT/$LABEL.xctrace.log" 2>&1 &
TRACE=$!
sleep 6
"$OUT/scroll" 6
wait "$TRACE"
# Hitches are counted only while frames are produced, so a shelf that never moved would read as a pass: the run fails
# unless the app reported the shelf's scroll offset travelling at least 300 points (P-06).
TRAVEL=$(python3 - "$W/perf-timeline.tsv" <<'PY'
import re, sys
try:
    offsets = [int(m.group(1)) for line in open(sys.argv[1]) if (m := re.search(r"shelfScroll\((-?\d+)\)", line))]
except OSError:
    offsets = []
print(max(offsets) - min(offsets) if offsets else 0)
PY
)
echo "shelf scroll travel: $TRAVEL points"
[ "$TRAVEL" -ge 300 ] || { echo "profile-scroll: the shelf did not scroll (travel $TRAVEL points): the hitch numbers prove nothing" >&2; exit 3; }
for table in hitches hitches-frame-lifetimes; do
  xcrun xctrace export --input "$OUT/$LABEL.trace" --xpath "/trace-toc/run/data/table[@schema=\"$table\"]" \
    > "$OUT/$LABEL-$table.xml"
done
echo "== $LABEL ($SEED)"
python3 "$HERE/profile-scroll/hitches.py" "$OUT/$LABEL"
echo "trace and logs: $OUT"
