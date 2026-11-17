#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Serves local multi-app HTML fixtures (paste-listener.html, gif-page.html) on an ephemeral localhost HTTP port,
# launches a Profile build of Pesto with PESTO_UITEST_REAL_PASTE=1, and runs MultiAppSuite.
#
# Usage: scripts/multi-app/run.sh [all|matrix|paste-as|entry-points|snippets|drag]
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SUITE="${1:-all}"
DERIVED=".build/xcode-profile"
OUT="$(mktemp -d)"
WORK="$OUT/pesto-multi-app"
mkdir -p "$WORK/commands"

if pgrep -x Pesto >/dev/null 2>&1; then
  echo "multi-app: quit any running Pesto instance first" >&2
  exit 1
fi

if [[ "${PESTO_SKIP_PROFILE_BUILD:-0}" != "1" ]]; then
  make generate >/dev/null
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
    || { tail -20 "$OUT/build.log" >&2; echo "multi-app: Profile build failed" >&2; exit 1; }
fi

APP="$DERIVED/Build/Products/Profile/Pesto.app"
BUNDLE_ENV="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$APP/Contents/Info.plist" | sed -n 's/^ *\(.*\) = \(.*\)$/\1=\2/p' | tr '\n' ' ')"
XCTEST_FW="${DEVELOPER_DIR}/Platforms/MacOSX.platform/Developer/Library/Frameworks"
swiftc -O -parse-as-library -F "$XCTEST_FW" -Xlinker -rpath -Xlinker "$XCTEST_FW" \
  -o "$OUT/MultiAppSuite" scripts/multi-app/MultiAppSuite.swift

# Start local static HTTP server for paste-listener.html and gif-page.html.
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory scripts/multi-app >"$OUT/http.log" 2>&1 &
HTTP_PID=$!

PID=""
cleanup() {
  kill "$HTTP_PID" 2>/dev/null || true
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$OUT"
}
trap cleanup EXIT INT

PESTO_UITEST_SESSION="multi-app" PESTO_UITEST_DIR="$WORK" PESTO_UITEST_SEED="marketing" \
  PESTO_UITEST_REAL_PASTE=1 PESTO_UITEST_ACCESSIBILITY=trusted \
  PESTO_UITEST_DEFAULT_hasOnboarded=true PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
  env $BUNDLE_ENV "$APP/Contents/MacOS/Pesto" -UITestMode >"$OUT/app.log" 2>&1 &
PID=$!

for _ in $(seq 1 300); do [ -f "$WORK/ready.json" ] && break; sleep 1; done
[ -f "$WORK/ready.json" ] || { echo "multi-app: Pesto never became ready" >&2; exit 1; }
sleep 1

"$OUT/MultiAppSuite" "$WORK" "$PORT" "$SUITE"
