#!/bin/bash
# SPDX-License-Identifier: MIT
# Runs only the checks that the files you changed can affect, and prints a short summary.
#
#   scripts/verify-changed.sh [base]      # base defaults to main; the working tree is included
#
# Always: lint, the Core tests and the hosted unit tests (about two minutes: they catch most cross-cutting breaks, such as
# a changed default or an import rule). Then the UI suites for the area the changed paths belong to. A path with no
# mapping runs every UI suite, so the shortcut can only run more than needed, never silently less. Run the full
# `scripts/verify.sh` once before merging.
set -uo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
BASE=${1:-main}
OUT=$(mktemp -d)

CHANGED=$( { git diff --name-only "$BASE"...HEAD; git diff --name-only; git ls-files --others --exclude-standard; } | sort -u)
[ -n "$CHANGED" ] || { echo "nothing changed against $BASE"; exit 0; }

SETTINGS="SettingsFlowTests SettingsReorganisationTests SettingsPolishTests SettingsEffectsTests ExclusionAndRetentionTests BackupSettingsTests AISettingsTests HistoryLockSettingsTests PrivacyDashboardTests"
SHELF="OverlayFlowTests KeyboardNavigationTests CardDetailPopoverTests SearchAndCollectionsTests SearchImprovementsTests DedupeFlowTests DeleteConfirmationTests SensitiveCardTests FileClipCardTests"
AUDIT="AccessibilityAuditTests"
SUITES=""
add() { SUITES="$SUITES $*"; }
RUN_ALL=0
while IFS= read -r file; do
  case "$file" in
    Sources/Features/Settings/*|Sources/Core/Runtime/SettingsIndex.swift|Sources/Core/Backup/*|Sources/Core/Pasteboard/Exclusion*|Tests/PestoUITests/Settings*|Tests/PestoUITests/ExclusionAndRetentionTests.swift|Tests/PestoUITests/BackupSettingsTests.swift)
      add "$SETTINGS $AUDIT" ;;
    Sources/Features/Grid/*|Sources/Features/Overlay/*|Sources/Features/CommandBar/*|Tests/PestoUITests/OverlayFlowTests.swift)
      add "$SHELF $AUDIT" ;;
    docs/*|*.md|decisions/*|scripts/*|Makefile|Tests/PestoCoreTests/*|Tests/PestoTests/*|Tests/PestoRegressionTests/*|Sources/Core/*|design/*)
      ;;
    *) RUN_ALL=1 ;;
  esac
done <<< "$CHANGED"

echo "== lint"
make lint > "$OUT/lint.log" 2>&1 && echo "pass" || { echo "FAIL"; grep -E "error:" "$OUT/lint.log" | head -5; }
echo "== Core tests"
swift test > "$OUT/core.log" 2>&1 && echo "pass: $(grep -E 'Test run with [0-9]+ tests' "$OUT/core.log" | tail -1 | sed 's/.*with //')" \
  || { echo "FAIL"; grep -E "✘|error:" "$OUT/core.log" | head -5; }
make generate > /dev/null 2>&1

ONLY=("-only-testing:PestoTests")
if [ "$RUN_ALL" = 1 ]; then
  ONLY+=("-only-testing:PestoUITests")
else
  for suite in $(echo "$SUITES" | tr ' ' '\n' | sort -u); do ONLY+=("-only-testing:PestoUITests/$suite"); done
fi
echo "== hosted + UI: ${ONLY[*]:1}"
xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "${ONLY[@]}" test > "$OUT/xcode.log" 2>&1
if grep -q "^\*\* TEST SUCCEEDED" "$OUT/xcode.log"; then
  echo "pass"
else
  echo "FAIL"
  grep -E "error: |Test Case .* failed|✘ Test " "$OUT/xcode.log" | grep -v "Unable to\|mdb_\|sandbox" | head -8 | cut -c1-220
fi
echo "logs: $OUT"
