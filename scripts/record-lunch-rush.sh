#!/bin/bash
# SPDX-License-Identifier: MIT
# Records one beat of the website's demo video ("The Lunch Rush", LunchRushRecordingTests) with ffmpeg's screen capture:
#   scripts/record-lunch-rush.sh a|b|c|d|e|f|g|h|i|j|all [light|dark]
# writes .build/lunch-rush/<beat>-<mode>.mov, cropped to the bottom strip of the brand backdrop.
# It changes no system setting. The run needs a person at the Mac: the terminal that runs this script must already have
# Screen Recording permission (System Settings > Privacy & Security > Screen & System Audio Recording), the Mac must be
# unlocked, Do Not Disturb on, and every other app and desktop clutter out of the way (the backdrop covers the desktop
# but notifications and other windows can still appear on top). The beat runs against a private copy of the app in
# -UITestMode, so the real clipboard, history and preferences are never touched.
set -euo pipefail
cd "$(dirname "$0")/.."

BEAT=${1:-}
MODE=${2:-light}
case "$BEAT" in a | b | c | d | e | f | g | h | all) ;; *)
  echo "usage: $0 a|b|c|d|e|f|g|h|i|j|all [light|dark]" >&2
  exit 2
  ;;
esac
command -v ffmpeg > /dev/null || { echo "ffmpeg is missing (brew install ffmpeg)" >&2; exit 1; }
if pgrep -x Pesto > /dev/null; then
  echo "A Pesto is running. Quit it first: the take must not show or disturb your real history." >&2
  exit 1
fi

DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export DEVELOPER_DIR
OUT=.build/lunch-rush
mkdir -p "$OUT"

# `-list_devices` always ends with an error exit, so it is read into a variable first and its status ignored.
devices=$(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 || true)
SCREEN=$(sed -n 's/.*\[\([0-9]*\)\] Capture screen 0.*/\1/p' <<< "$devices" | head -1)
[ -n "$SCREEN" ] || { echo "ffmpeg sees no screen to capture" >&2; exit 1; }

# A one-second probe: without Screen Recording permission macOS hands ffmpeg black frames or an error.
probe="$OUT/.probe.png"
rm -f "$probe"
ffmpeg -hide_banner -loglevel error -y -f avfoundation -framerate 30 -capture_cursor 1 -i "$SCREEN:none" -frames:v 1 "$probe" 2>/dev/null || true
if [ ! -s "$probe" ] || [ "$(wc -c < "$probe")" -lt 20000 ]; then
  echo "Screen capture returned nothing useful. Grant Screen Recording to this terminal (System Settings > Privacy & Security), restart it and try again. This script never changes that setting." >&2
  exit 1
fi
rm -f "$probe"

XCB=(xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Debug -destination 'platform=macOS'
  -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
[ -f Pesto.xcodeproj/project.pbxproj ] || make generate
"${XCB[@]}" build-for-testing > "$OUT/build.log" 2>&1 || { echo "build failed; see $OUT/build.log" >&2; exit 1; }

# Crop: the bottom strip of the backdrop, which holds the shelf and the fill-in sheet but not the "Automation Running" notice
# macOS draws in the middle of the screen during a UI test. Override with PESTO_CROP="w:h:x:y" in pixels for another display.
CROP=${PESTO_CROP:-3024:1224:0:740}

record_beat() {
  local letter=$1 name test
  case "$letter" in
    a) name=test_a_maskedCardPastesTheRealNumber ;;
    b) name=test_b_supportReplyAsksThreeQuestions ;;
    c) name=test_c_auditFindsTheAnswer ;;
    d) name=test_d_pinnedCommandPastes ;;
    e) name=test_e_supplierLinksCollection ;;
    f) name=test_f_agentPromptFillsIn ;;
    g) name=test_g_pasteAllJoinsTheIngredients ;;
    h) name=test_h_sensitivePictureShowAndHide ;;
    i) name=test_i_fourThemes ;;
    j) name=test_j_quickSnippetPastesAtOnce ;;
  esac
  test="PestoUITests/LunchRushRecordingTests/$name"
  local file="$OUT/$letter-$MODE.mov"
  rm -f "$file"
  ffmpeg -hide_banner -loglevel error -y -f avfoundation -framerate 30 -capture_cursor 1 -i "$SCREEN:none" \
    -vf "crop=$CROP,scale=1920:-2:flags=lanczos" -c:v libx264 -crf 16 -preset veryfast -pix_fmt yuv420p "$file" &
  local recorder=$!
  sleep 1
  local status=0
  env TEST_RUNNER_PESTO_LUNCH_RUSH_MODE="$MODE" "${XCB[@]}" test-without-building -only-testing:"$test" > "$OUT/$letter.log" 2>&1 || status=$?
  sleep 1
  kill -INT "$recorder" 2>/dev/null || true
  wait "$recorder" 2>/dev/null || true
  if [ "$status" -ne 0 ]; then echo "beat $letter failed; see $OUT/$letter.log" >&2; return 1; fi
  echo "$file  $(( $(wc -c < "$file") / 1000000 )) MB"
}

if [ "$BEAT" = all ]; then
  for letter in a b c d e f g h i j; do record_beat "$letter"; done
else
  record_beat "$BEAT"
fi
