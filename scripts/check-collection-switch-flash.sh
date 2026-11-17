#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Launches a Profile build of Pesto on the 5,000-clip history, opens OverlayPanel, and runs
# `check-collection-switch-flash.swift` (ScreenCaptureKit SCStream at up to 120 Hz) while cycling ⌘]/⌘[.
#
# Usage: scripts/check-collection-switch-flash.sh [cycles]
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CYCLES="${1:-12}"
DERIVED=".build/xcode-profile"
OUT="$(mktemp -d)"
WORK="$OUT/pesto-flash-work"
mkdir -p "$WORK/commands"

if pgrep -x Pesto >/dev/null 2>&1; then
  echo "check-collection-switch-flash: quit any running Pesto instance first" >&2
  exit 1
fi

if [[ "${PESTO_SKIP_PROFILE_BUILD:-0}" != "1" ]]; then
  make generate >/dev/null
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
    || { tail -20 "$OUT/build.log" >&2; echo "check-collection-switch-flash: Profile build failed" >&2; exit 1; }
fi

APP="$DERIVED/Build/Products/Profile/Pesto.app"
BUNDLE_ENV="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$APP/Contents/Info.plist" | sed -n 's/^ *\(.*\) = \(.*\)$/\1=\2/p' | tr '\n' ' ')"
swiftc -O -parse-as-library -o "$OUT/check-flash" scripts/check-collection-switch-flash.swift

PESTO_UITEST_SESSION="flash" PESTO_UITEST_DIR="$WORK" PESTO_UITEST_SEED="large" PESTO_UITEST_ACCESSIBILITY=trusted \
  PESTO_UITEST_DEFAULT_hasOnboarded=true PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
  env $BUNDLE_ENV "$APP/Contents/MacOS/Pesto" -UITestMode >"$OUT/app.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -rf "$OUT"' EXIT

command_file() {
  printf '%s' "$1" >"$WORK/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"
}

for _ in $(seq 1 300); do [ -f "$WORK/ready.json" ] && break; sleep 1; done
[ -f "$WORK/ready.json" ] || { echo "check-collection-switch-flash: Pesto never became ready" >&2; exit 1; }

command_file showOverlay
sleep 1.5
"$OUT/check-flash" "$WORK" "$CYCLES"
