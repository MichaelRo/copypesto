#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Drives a Profile build of Pesto launched via `open -a` (so LaunchServices applies Info.plist LSEnvironment)
# through configurable soak cycles: live mixed copies, shelf open/close, collection switches, hover dwell,
# Quick Look, and retention prunes. Samples `footprint`, `leaks`, and `vmmap -summary`, asserting:
#   - MallocLargeCache=0 in process environment
#   - physical footprint < BUDGET_MB (default 150 MB)
#   - 0 leaks reported by `leaks`
#   - flat post-warmup footprint slope
#
# Usage: scripts/soak-memory.sh [cycles] [budget-in-MB]
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CYCLES="${1:-5}"
BUDGET_MB="${2:-150}"
SEED="${SOAK_SEED:-large}"
DERIVED=".build/xcode-profile"
OUT="$(mktemp -d)"
WORK="$OUT/pesto-soak-work"
mkdir -p "$WORK/commands"

if pgrep -x Pesto >/dev/null 2>&1; then
  echo "soak-memory: quit any running Pesto instance first" >&2
  exit 1
fi

if [[ "${PESTO_SKIP_PROFILE_BUILD:-0}" != "1" ]]; then
  make generate >/dev/null
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
    || { tail -20 "$OUT/build.log" >&2; echo "soak-memory: Profile build failed" >&2; exit 1; }
fi

APP="$OUT/Pesto.app"
ditto "$DERIVED/Build/Products/Profile/Pesto.app" "$APP"
rm -rf "$APP"/Contents/PlugIns/*.xctest "$APP"/Contents/PlugIns/*.xctest.dSYM
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

command_file() {
  printf '%s' "$1" >"$WORK/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"
}

PID=""
cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$OUT"
}
trap cleanup EXIT

# Launch via `open -a` so LaunchServices applies Info.plist's LSEnvironment (MallocLargeCache=0).
open -n -a "$APP" \
  --env "PESTO_UITEST_SESSION=soak" \
  --env "PESTO_UITEST_DIR=$WORK" \
  --env "PESTO_UITEST_SEED=$SEED" \
  --env "PESTO_UITEST_ACCESSIBILITY=trusted" \
  --env "PESTO_UITEST_REAL_PASTE=1" \
  --env "PESTO_UITEST_DEFAULT_hasOnboarded=true" \
  --env "PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false" \
  --env "PESTO_UITEST_DEFAULT_nsfwMode=show" \
  --env "PESTO_UITEST_DEFAULT_maxHistoryCount=5000" \
  --args -UITestMode

for _ in $(seq 1 300); do
  [ -f "$WORK/ready.json" ] && break
  sleep 1
done
[ -f "$WORK/ready.json" ] || { echo "soak-memory: Pesto never became ready" >&2; exit 1; }

PID=$(pgrep -n -f "$APP/Contents/MacOS/Pesto" || pgrep -n -x Pesto || true)
[ -n "$PID" ] || { echo "soak-memory: could not resolve Pesto PID" >&2; exit 1; }

if ! ps eww -p "$PID" | grep -q "MallocLargeCache=0"; then
  echo "soak-memory: FAIL — MallocLargeCache=0 not set in open -a environment" >&2
  exit 1
fi
echo "ok    MallocLargeCache=0 verified on open -a (PID $PID)"

sample_footprint_mb() {
  local line
  line="$(footprint "$PID" 2>/dev/null | grep -m1 -E 'Footprint:' || true)"
  [ -n "$line" ] || return 1
  echo "$line" | sed -E 's/.*Footprint: *([0-9.]+) *([KMG]B).*/\1 \2/' \
    | awk '{ if ($2=="KB") printf "%.2f", $1/1024; else if ($2=="GB") printf "%.2f", $1*1024; else printf "%.2f", $1 }'
}

# Warmup cycle: open shelf, cycle collections, close shelf.
command_file showOverlay
sleep 2
command_file benchCycleCollections
sleep 3
command_file hideOverlay
sleep 2

SAMPLES=()
echo "soak-memory: running $CYCLES soak cycles (seed=$SEED, budget=${BUDGET_MB} MB)..."

for cycle in $(seq 1 "$CYCLES"); do
  # 1. Mixed copies (text, URL, code) to exercise capture + retention pruning.
  printf 'Soak cycle %d text clip %s' "$cycle" "$(uuidgen)" | pbcopy
  sleep 0.3
  printf 'https://example.com/pesto/soak/%d' "$cycle" | pbcopy
  sleep 0.3
  printf 'func soak%d() -> Int { %d }\n' "$cycle" "$cycle" | pbcopy
  sleep 0.4

  # 2. Open shelf, step arrow keys (triggers hover card / selection), cycle collections, Quick Look toggle (Space), close.
  command_file showOverlay
  sleep 1
  command_file benchArrowSteps
  sleep 2
  command_file benchCycleCollections
  sleep 2
  osascript -e 'tell application "System Events" to keystroke " "' >/dev/null 2>&1 || true
  sleep 0.8
  osascript -e 'tell application "System Events" to keycode 53' >/dev/null 2>&1 || true
  sleep 0.4
  command_file hideOverlay
  sleep 2

  mb="$(sample_footprint_mb)"
  SAMPLES+=("$mb")
  echo "cycle $cycle/$CYCLES: ${mb} MB"
  awk -v mb="$mb" -v budget="$BUDGET_MB" 'BEGIN { exit (mb + 0 < budget + 0) ? 0 : 1 }' \
    || { echo "soak-memory: FAIL — footprint ${mb} MB >= ${BUDGET_MB} MB on cycle $cycle" >&2; exit 1; }
done

# Post-warmup slope check (linear regression over samples[1..N-1] if >= 2 cycles).
if [ "${#SAMPLES[@]}" -ge 3 ]; then
  SLOPE_CHECK=$(python3 - "${SAMPLES[@]}" <<'PY'
import sys
vals = [float(x) for x in sys.argv[1:]]
post = vals[1:]
n = len(post)
xs = list(range(n))
mx = sum(xs) / n
my = sum(post) / n
num = sum((x - mx) * (y - my) for x, y in zip(xs, post))
den = sum((x - mx) ** 2 for x in xs) or 1.0
slope = num / den
delta = max(post) - min(post)
print(f"{slope:.3f} {delta:.2f}")
if slope > 2.5:
    sys.exit(1)
PY
  ) || { echo "soak-memory: FAIL — post-warmup footprint slope > 2.5 MB/cycle ($SLOPE_CHECK)" >&2; exit 1; }
  echo "ok    post-warmup slope/delta: $SLOPE_CHECK (MB/cycle, MB)"
fi

vmmap -summary "$PID" >"$OUT/vmmap-summary.txt" 2>&1 || true
echo "ok    vmmap -summary captured ($OUT/vmmap-summary.txt)"

LEAKS_OUT="$OUT/leaks.txt"
if ! leaks "$PID" >"$LEAKS_OUT" 2>&1; then
  cat "$LEAKS_OUT" >&2
  echo "soak-memory: FAIL — leaks exited non-zero" >&2
  exit 1
fi
LEAK_COUNT=$(grep -Eo '[0-9]+ leaks for [0-9]+ total leaked bytes' "$LEAKS_OUT" | awk '{print $1}' | head -1 || echo "0")
if [ "${LEAK_COUNT:-0}" != "0" ]; then
  cat "$LEAKS_OUT" >&2
  echo "soak-memory: FAIL — detected $LEAK_COUNT leaks" >&2
  exit 1
fi
echo "ok    leaks reported 0 leaks"
echo "soak-memory: PASS"
