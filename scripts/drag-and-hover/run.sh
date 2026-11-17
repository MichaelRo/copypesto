#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds and runs the standalone CGEvent + AXObserver drag-and-hover harness against a Profile build of Pesto.
#
# Usage: scripts/drag-and-hover/run.sh [all|chip-drop|card-reorder|chip-reorder|hover-copy|onboarding-strip|ax-announcements]
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SUITE="${1:-all}"
DERIVED=".build/xcode-profile"
OUT="$(mktemp -d)"
WORK="$OUT/pesto-drag-hover"
mkdir -p "$WORK/commands"

if pgrep -x Pesto >/dev/null 2>&1; then
  echo "drag-and-hover: quit any running Pesto instance first" >&2
  exit 1
fi

if [[ "${PESTO_SKIP_PROFILE_BUILD:-0}" != "1" ]]; then
  make generate >/dev/null
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
    || { tail -20 "$OUT/build.log" >&2; echo "drag-and-hover: Profile build failed" >&2; exit 1; }
fi

APP="$DERIVED/Build/Products/Profile/Pesto.app"
BUNDLE_ENV="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$APP/Contents/Info.plist" | sed -n 's/^ *\(.*\) = \(.*\)$/\1=\2/p' | tr '\n' ' ')"
swiftc -O -parse-as-library -o "$OUT/DragAndHoverHarness" scripts/drag-and-hover/DragAndHoverHarness.swift

EXTRA_ARGS="-UITestMode"
if [ "$SUITE" = "onboarding-strip" ]; then
  EXTRA_ARGS="-UITestMode -UITestMotion"
fi

PESTO_UITEST_SESSION="drag-hover" PESTO_UITEST_DIR="$WORK" PESTO_UITEST_SEED="marketing" PESTO_UITEST_ACCESSIBILITY=trusted \
  PESTO_UITEST_DEFAULT_hasOnboarded=true PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
  env $BUNDLE_ENV "$APP/Contents/MacOS/Pesto" $EXTRA_ARGS >"$OUT/app.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -rf "$OUT"' EXIT INT

for _ in $(seq 1 300); do [ -f "$WORK/ready.json" ] && break; sleep 1; done
[ -f "$WORK/ready.json" ] || { echo "drag-and-hover: Pesto never became ready" >&2; exit 1; }
sleep 1

"$OUT/DragAndHoverHarness" "$WORK" "$SUITE"
