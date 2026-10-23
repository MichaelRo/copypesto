#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Re-runs only the hosted and UI tests that failed in a gate run (the newest, or the run folder given), the usual
# answer to the first-run "Timed out while enabling automation mode" failures. A partial run proves those tests and
# nothing else: only a full scripts/verify.sh counts as the gate.
#
#   scripts/verify-rerun-failed.sh [.build/verify/<run>]
set -uo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${VERIFY_CAFFEINATED:-}" ]] && command -v caffeinate >/dev/null; then
  exec env VERIFY_CAFFEINATED=1 caffeinate -dis "$0" "$@"
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if pgrep -x Pesto >/dev/null; then
  echo "verify-rerun-failed.sh: Pesto is running. Quit it (menu bar icon > Quit Pesto) and run this again." >&2
  exit 2
fi

RUN_DIR="${1:-$(ls -td .build/verify/*/ 2>/dev/null | head -1)}"
SUMMARY="${RUN_DIR%/}/tests-summary.json"
[[ -f "$SUMMARY" ]] || { echo "no tests-summary.json in '$RUN_DIR': run scripts/verify.sh first" >&2; exit 2; }

ONLY=()
while IFS= read -r argument; do ONLY+=("$argument"); done < <(python3 scripts/verify_failures.py "$SUMMARY" --only-testing)
if [[ ${#ONLY[@]} -eq 0 ]]; then
  echo "nothing failed in $RUN_DIR"
  exit 0
fi
echo "re-running ${#ONLY[@]} failed test target(s) from $RUN_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT="${RUN_DIR%/}/rerun-$STAMP.xcresult"
LOG="${RUN_DIR%/}/rerun-$STAMP.log"
make generate >/dev/null 2>&1
caffeinate -u -t 3 2>/dev/null || true
env TEST_RUNNER_PESTO_SCREENSHOT_DIR="$PWD/.build/ui-screenshots/rerun-$STAMP" xcodebuild \
  -project Pesto.xcodeproj -scheme Pesto -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build/xcode \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  "${ONLY[@]}" -resultBundlePath "$RESULT" test >"$LOG" 2>&1
CODE=$?

xcrun xcresulttool get test-results summary --path "$RESULT" --compact >"${RESULT%.xcresult}-summary.json" 2>/dev/null
python3 - "${RESULT%.xcresult}-summary.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
print("passed=%s failed=%s skipped=%s" % (s.get("passedTests", "?"), s.get("failedTests", "?"), s.get("skippedTests", "?")))
PY
python3 scripts/verify_failures.py "${RESULT%.xcresult}-summary.json"
echo "log: $LOG"
if [[ $CODE -eq 0 ]]; then echo "RESULT: PASS (partial run: not the gate)"; else echo "RESULT: FAIL"; fi
exit $CODE
