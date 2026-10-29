#!/bin/bash
# SPDX-License-Identifier: MIT
# Records one beat of the website's demo video ("The Lunch Rush", LunchRushRecordingTests) with a ScreenCaptureKit window recorder:
#   scripts/record-lunch-rush.sh a|b|c|d|e|f|g|i|j|all [light|dark]
# writes .build/lunch-rush/<beat>-<mode>.mov: Pesto's own windows only (the brand backdrop, shelf and sheets), at the display's pixel scale.
# It changes no system setting. The run needs a person at the Mac: the terminal that runs this script must already have
# Screen Recording permission (System Settings > Privacy & Security > Screen & System Audio Recording), the Mac must be
# unlocked and left alone while it runs. Only Pesto's own windows are recorded, so other apps, the Dock and the notice macOS
# draws during a UI test are not in the take. The beat runs against a private copy of the app in -UITestMode, so the real
# clipboard, history and preferences are never touched.
set -euo pipefail
cd "$(dirname "$0")/.."

BEAT=${1:-}
MODE=${2:-light}
case "$MODE" in light|dark) ;; *) echo "mode must be light or dark, not $MODE" >&2; exit 2 ;; esac
case "$BEAT" in a | b | c | d | e | f | g | i | j | all) ;; *)
  echo "usage: $0 a|b|c|d|e|f|g|i|j|all [light|dark]" >&2
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

# The recorder captures only Pesto's own windows (ScreenCaptureKit), so the notice and dimming macOS draws during a UI test,
# and every other window on the Mac, stay out of the take. It needs Screen Recording permission for this terminal.
RECORDER="$OUT/window-recorder"
if [ ! -x "$RECORDER" ] || [ scripts/dev/window-recorder.swift -nt "$RECORDER" ]; then
  swiftc -O -swift-version 5 scripts/dev/window-recorder.swift -o "$RECORDER" 2> "$OUT/recorder-build.log" || { echo "cannot build the recorder; see $OUT/recorder-build.log" >&2; exit 1; }
fi

XCB=(xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Debug -destination 'platform=macOS'
  -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
[ -f Pesto.xcodeproj/project.pbxproj ] || make generate
"${XCB[@]}" build-for-testing > "$OUT/build.log" 2>&1 || { echo "build failed; see $OUT/build.log" >&2; exit 1; }

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
    i) name=test_i_fourThemes ;;
    j) name=test_j_quickSnippetPastesAtOnce ;;
  esac
  test="PestoUITests/LunchRushRecordingTests/$name"
  local file="$OUT/$letter-$MODE.mov"
  rm -f "$file"
  "$RECORDER" "$file" > "$OUT/$letter-recorder.log" 2>&1 &
  local recorder=$!
  sleep 1
  local status=0
  env TEST_RUNNER_PESTO_LUNCH_RUSH_MODE="$MODE" "${XCB[@]}" test-without-building -only-testing:"$test" > "$OUT/$letter.log" 2>&1 || status=$?
  sleep 1
  kill -INT "$recorder" 2>/dev/null || true
  wait "$recorder" 2>/dev/null || true
  if [ "$status" -ne 0 ]; then echo "beat $letter failed; see $OUT/$letter.log" >&2; return 1; fi
  if [ ! -s "$file" ]; then echo "beat $letter recorded nothing: $(cat "$OUT/$letter-recorder.log")" >&2; return 1; fi
  echo "$file  $(( $(wc -c < "$file") / 1000000 )) MB"
}

if [ "$BEAT" = all ]; then
  for letter in a b c d e f g i j; do record_beat "$letter"; done
else
  record_beat "$BEAT"
fi
