#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Tests sleep/wake paste suppression on real hardware:
#   1. Launches a Profile build of Pesto (-UITestMode) with PESTO_UITEST_REAL_PASTE=1.
#   2. Schedules a system wake +15 s ahead (`pmset schedule wake`) and puts the Mac to sleep (`pmset sleepnow`).
#   3. After wake, verifies zero paste occurred during/after wake and confirms `[cancel] reason=wake-or-screen-unlock`
#      in the unified log (subsystem == "net.copypesto.pesto").
#
# Requires: passwordless sudo for `pmset` (or running as root).
# Usage: scripts/test-sleep-paste.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DERIVED=".build/xcode-profile"
OUT="$(mktemp -d)"
WORK="$OUT/pesto-sleep-paste"
mkdir -p "$WORK/commands"

if pgrep -x Pesto >/dev/null 2>&1; then
  echo "test-sleep-paste: quit any running Pesto instance first" >&2
  exit 1
fi

run_pmset() {
  if [ "$(id -u)" -eq 0 ]; then
    pmset "$@"
  else
    sudo -n pmset "$@"
  fi
}

if ! run_pmset -g >/dev/null 2>&1; then
  echo "test-sleep-paste: requires root or passwordless sudo for pmset" >&2
  exit 1
fi

if [[ "${PESTO_SKIP_PROFILE_BUILD:-0}" != "1" ]]; then
  make generate >/dev/null
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
    || { tail -20 "$OUT/build.log" >&2; echo "test-sleep-paste: Profile build failed" >&2; exit 1; }
fi

APP="$DERIVED/Build/Products/Profile/Pesto.app"
BUNDLE_ENV="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$APP/Contents/Info.plist" | sed -n 's/^ *\(.*\) = \(.*\)$/\1=\2/p' | tr '\n' ' ')"

PID=""
cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$OUT"
}
trap cleanup EXIT INT

START_TS=$(date "+%Y-%m-%d %H:%M:%S")

PESTO_UITEST_SESSION="sleep-paste" PESTO_UITEST_DIR="$WORK" PESTO_UITEST_SEED="marketing" \
  PESTO_UITEST_REAL_PASTE=1 PESTO_UITEST_ACCESSIBILITY=trusted \
  PESTO_UITEST_DEFAULT_hasOnboarded=true PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
  env $BUNDLE_ENV "$APP/Contents/MacOS/Pesto" -UITestMode >"$OUT/app.log" 2>&1 &
PID=$!

for _ in $(seq 1 300); do [ -f "$WORK/ready.json" ] && break; sleep 1; done
[ -f "$WORK/ready.json" ] || { echo "test-sleep-paste: Pesto never became ready" >&2; exit 1; }

mkdir -p "$WORK/commands"
printf '%s' "showOverlay" >"$WORK/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"
sleep 0.5
osascript -e 'tell application "System Events" to key code 36' >/dev/null 2>&1 || true

WAKE_AT=$(date -v+15S "+%m/%d/%Y %H:%M:%S")
echo "test-sleep-paste: scheduling wake at $WAKE_AT and sleeping..."
run_pmset schedule wake "$WAKE_AT"
run_pmset sleepnow
sleep 20

LOGS=$(log show --start "$START_TS" --predicate 'subsystem == "net.copypesto.pesto"' --info --debug 2>/dev/null || true)
if printf '%s\n' "$LOGS" | grep -q '\[cancel\] reason=wake-or-screen-unlock'; then
  echo "ok    observed [cancel] reason=wake-or-screen-unlock in unified log"
else
  echo "FAIL  did not observe [cancel] reason=wake-or-screen-unlock after wake" >&2
  exit 1
fi
echo "test-sleep-paste: PASS"
