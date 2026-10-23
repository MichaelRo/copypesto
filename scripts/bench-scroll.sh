#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds a Profile copy of Pesto (Release, plus the test hooks the harness needs), signs it with the development certificate, and records the shelf's scrolling on the
# `mixed` history (large pictures, links, code) and on the 5,000-text-clip history, printing the hitch summaries one under
# the other. Run it before and after a change to the shelf and compare. Needs the Mac unlocked and awake.
#
#   scripts/bench-scroll.sh [label]        # label names the run in the output (default: the git branch)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
LABEL=${1:-$(git rev-parse --abbrev-ref HEAD | tr '/' '-')}
IDENTITY="Pesto Development"
OUT=$(mktemp -d)
export PROFILE_OUT="$OUT"

make generate > /dev/null
xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
  -derivedDataPath .build/xcode-profile CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > "$OUT/build.log" 2>&1
APP="$OUT/Pesto.app"
ditto .build/xcode-profile/Build/Products/Profile/Pesto.app "$APP"
rm -rf "$APP"/Contents/PlugIns/*.xctest "$APP"/Contents/PlugIns/*.xctest.dSYM
codesign -f -s "$IDENTITY" --entitlements Sources/Controls/PestoControls.entitlements \
  "$APP/Contents/PlugIns/PestoControls.appex" > /dev/null 2>&1
codesign -f -s "$IDENTITY" --entitlements Sources/Resources/Pesto.entitlements "$APP" > /dev/null 2>&1

FAILED=0
for seed in ${SEEDS:-mixed large pictures}; do
  RESULT=$(scripts/profile-scroll.sh "$LABEL-$seed" "$APP" "$seed" | grep -v "^trace and logs")
  echo "$RESULT"
  # Fails when the run shows far more hitches than the recorded baseline (docs/perf/budgets-2026-10.md).
  echo "$RESULT" | python3 scripts/profile-scroll/check-budget.py "$seed" || FAILED=1
done
echo "traces: $OUT"
exit $FAILED
