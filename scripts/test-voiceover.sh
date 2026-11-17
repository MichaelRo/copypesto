#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Drives a live VoiceOver.sdef osascript sweep across Pesto's OverlayPanel (cards, filter chips, actions)
# and verifies spoken VoiceOver announcements (`last phrase`). Restores VoiceOver state on EXIT.
#
# Usage: scripts/test-voiceover.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DERIVED=".build/xcode-profile"
OUT="$(mktemp -d)"
WORK="$OUT/pesto-voiceover"
mkdir -p "$WORK/commands"

if pgrep -x Pesto >/dev/null 2>&1; then
  echo "test-voiceover: quit any running Pesto instance first" >&2
  exit 1
fi

VO_WAS_RUNNING=0
if pgrep -x VoiceOver >/dev/null 2>&1; then
  VO_WAS_RUNNING=1
fi

PID=""
cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  if [ "$VO_WAS_RUNNING" -eq 0 ]; then
    osascript -e 'tell application "VoiceOver" to quit' >/dev/null 2>&1 || true
  fi
  rm -rf "$OUT"
}
trap cleanup EXIT INT

if [[ "${PESTO_SKIP_PROFILE_BUILD:-0}" != "1" ]]; then
  make generate >/dev/null
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
    || { tail -20 "$OUT/build.log" >&2; echo "test-voiceover: Profile build failed" >&2; exit 1; }
fi

APP="$DERIVED/Build/Products/Profile/Pesto.app"
BUNDLE_ENV="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$APP/Contents/Info.plist" 2>/dev/null | sed -n 's/^ *\(.*\) = \(.*\)$/\1=\2/p' | tr '\n' ' ' || true)"

PESTO_UITEST_SESSION="voiceover" PESTO_UITEST_DIR="$WORK" PESTO_UITEST_SEED="marketing" \
  PESTO_UITEST_ACCESSIBILITY=trusted PESTO_UITEST_DEFAULT_hasOnboarded=true \
  PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
  env $BUNDLE_ENV "$APP/Contents/MacOS/Pesto" -UITestMode >"$OUT/app.log" 2>&1 &
PID=$!

for _ in $(seq 1 300); do [ -f "$WORK/ready.json" ] && break; sleep 1; done
[ -f "$WORK/ready.json" ] || { echo "test-voiceover: Pesto never became ready" >&2; exit 1; }

osascript -e 'tell application "System Events" to set frontmost of process "Pesto" to true' >/dev/null 2>&1 || true
printf '%s' "showOverlay" >"$WORK/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"
sleep 1.2

# Launch VoiceOver first (calling `activate` inside `tell application "VoiceOver"` hangs with -1712).
if ! pgrep -x VoiceOver >/dev/null 2>&1; then
  open -a VoiceOver >/dev/null 2>&1 || true
  sleep 2
fi

# Sweep VoiceOver cursor via VoiceOver.sdef (`tell application "VoiceOver"`).
VO_OUTPUT=$(osascript <<'APPLESCRIPT'
tell application "VoiceOver"
  tell commander to perform command "move right"
  delay 0.5
  set phrase1 to content of last phrase
  tell commander to perform command "move right"
  delay 0.5
  set phrase2 to content of last phrase
  return phrase1 & " || " & phrase2
end tell
APPLESCRIPT
)

echo "voiceover phrases: $VO_OUTPUT"
if [ -z "${VO_OUTPUT// /}" ] || [ "$VO_OUTPUT" = " || " ] || [[ "$VO_OUTPUT" == *"missing value"* && "$VO_OUTPUT" != *[a-zA-Z0-9]* ]]; then
  echo "FAIL: VoiceOver produced empty phrases" >&2
  exit 1
fi
if [[ "$VO_OUTPUT" == *"missing value,  || , missing value"* ]]; then
  echo "FAIL: VoiceOver returned only missing value" >&2
  exit 1
fi
echo "test-voiceover: PASS"
