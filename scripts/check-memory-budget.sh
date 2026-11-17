#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Launches a Profile build (Release with the test hooks) on the 5,000-clip "large" history, shows the shelf, lets it
# settle and fails when the app's physical footprint is over the budget in AGENTS.md (150 MB). Writes the number to
# stdout so a run records it. Needs no Accessibility and no trackpad; the Mac should be unlocked, like the UI tests.
#
#   scripts/check-memory-budget.sh [budget-in-MB] [closed|open|pictures]
#   scripts/check-memory-budget.sh --idle-cpu [max-cpu-percent]
#
# closed: the shelf never shown. open: shown over the 5,000 text clips. pictures: shown over 300 large pictures and
# walked to its last clip, so every 480-pixel thumbnail is drawn once (P-06).
# --idle-cpu: measures 30 s idle CPU (< 0.5% default) with SyncFolderWatcher active.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDLE_CPU_MODE=0
IDLE_CPU_BUDGET="0.5"
if [[ "${1:-}" == "--idle-cpu" ]]; then
  IDLE_CPU_MODE=1
  IDLE_CPU_BUDGET="${2:-0.5}"
  BUDGET_MB="150"
  SHELF="closed"
else
  BUDGET_MB="${1:-150}"
  SHELF="${2:-open}"
fi
SEED=large
[ "$SHELF" = pictures ] && SEED=pictures
DERIVED=.build/xcode-profile
APP="$DERIVED/Build/Products/Profile/Pesto.app"
OUT="$(mktemp -d)"
WORK="$OUT/pesto-memory-work"
mkdir -p "$WORK/commands"

if [[ "${PESTO_SKIP_PROFILE_BUILD:-0}" != "1" ]]; then
  make generate >/dev/null
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
    || { tail -20 "$OUT/build.log" >&2; echo "check-memory-budget: the Profile build failed" >&2; exit 1; }
  rm -rf "$APP"/Contents/PlugIns/*.xctest "$APP"/Contents/PlugIns/*.xctest.dSYM
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1
fi

# Info.plist's LSEnvironment (MallocLargeCache=0) is applied by LaunchServices only; apply it here and check it took (P-02).
BUNDLE_ENV="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$APP/Contents/Info.plist" | sed -n 's/^ *\(.*\) = \(.*\)$/\1=\2/p' | tr '\n' ' ')"

SYNC_DEFAULT="false"
if [ "$IDLE_CPU_MODE" = "1" ]; then
  SYNC_DEFAULT="true"
  mkdir -p "$WORK/sync-folder"
fi

PESTO_UITEST_SESSION="memory" PESTO_UITEST_DIR="$WORK" PESTO_UITEST_SEED="$SEED" PESTO_UITEST_ACCESSIBILITY=trusted \
  PESTO_UITEST_DEFAULT_hasOnboarded=true PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
  PESTO_UITEST_DEFAULT_nsfwMode=show PESTO_UITEST_DEFAULT_syncEnabled="$SYNC_DEFAULT" \
  env $BUNDLE_ENV "$APP/Contents/MacOS/Pesto" -UITestMode >"$OUT/app.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -rf "$OUT"' EXIT
command_file() { printf '%s' "$1" >"$WORK/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"; }
for _ in $(seq 1 900); do [ -f "$WORK/ready.json" ] && break; sleep 1; done
if [ -n "$BUNDLE_ENV" ] && ! ps eww -p "$PID" | grep -q "MallocLargeCache=0"; then
  echo "check-memory-budget: the app runs without the environment its Info.plist sets (MallocLargeCache=0)" >&2
  exit 1
fi
[ -f "$WORK/ready.json" ] || { echo "check-memory-budget: the app never became ready" >&2; exit 1; }
if [ "$IDLE_CPU_MODE" = "1" ]; then
  sleep 5
  parse_cputime() {
    ps -o time= -p "$PID" | awk -F: '{
      if (NF == 3) print ($1 * 3600) + ($2 * 60) + $3;
      else if (NF == 2) print ($1 * 60) + $2;
      else print $1;
    }'
  }
  T0=$(parse_cputime)
  sleep 30
  T1=$(parse_cputime)
  CPU_PCT=$(awk -v t0="$T0" -v t1="$T1" 'BEGIN { printf "%.3f", ((t1 - t0) / 30.0) * 100.0 }')
  echo "idle-cpu: ${CPU_PCT}% over 30s with SyncFolderWatcher active (budget < ${IDLE_CPU_BUDGET}%)"
  awk -v cpu="$CPU_PCT" -v budget="$IDLE_CPU_BUDGET" 'BEGIN { exit (cpu + 0 < budget + 0) ? 0 : 1 }' \
    || { echo "check-memory-budget: idle CPU ${CPU_PCT}% >= ${IDLE_CPU_BUDGET}%" >&2; exit 1; }
  exit 0
fi
if [ "$SHELF" != closed ]; then
  command_file showOverlay
fi
if [ "$SHELF" = pictures ]; then
  sleep 5
  command_file walkShelfToEnd
  for _ in $(seq 1 300); do [ -f "$WORK/walk-done" ] && break; sleep 1; done
  [ -f "$WORK/walk-done" ] || { echo "check-memory-budget: the shelf never reached its last clip" >&2; exit 1; }
fi
# Wait up to 40 s for background thumbnail decoding and runtime caches to settle.
MB=""
for _ in $(seq 1 20); do
  sleep 2
  LINE="$(footprint "$PID" 2>/dev/null | grep -m1 -E 'Footprint:' || true)"
  [ -n "$LINE" ] || continue
  MB="$(echo "$LINE" | sed -E 's/.*Footprint: *([0-9.]+) *([KMG]B).*/\1 \2/' | awk '{ if ($2=="KB") print $1/1024; else if ($2=="GB") print $1*1024; else print $1 }')"
  if awk -v mb="$MB" -v budget="$BUDGET_MB" 'BEGIN { exit (mb + 0 < budget + 0) ? 0 : 1 }'; then
    break
  fi
done

[ -n "$MB" ] || { echo "check-memory-budget: footprint printed nothing for pid $PID" >&2; exit 1; }
echo "memory: ${MB} MB footprint on the ${SEED} history, shelf ${SHELF} (budget ${BUDGET_MB} MB)"
awk -v mb="$MB" -v budget="$BUDGET_MB" 'BEGIN { exit (mb + 0 < budget + 0) ? 0 : 1 }' \
  || { echo "check-memory-budget: over the budget" >&2; exit 1; }
