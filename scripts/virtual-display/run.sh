#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs VirtualDisplayTest against a Profile build of Pesto, testing CGVirtualDisplay multi-screen
# panel placement, shelfPosition=underNotch + autoHideMenuBar, Stage Manager, full-screen, and
# #FFFFFF/#000000 wallpaper menu-bar icon contrast (with original wallpaper & Stage Manager restore on EXIT/ERR/INT).
#
# Usage: scripts/virtual-display/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DERIVED=".build/xcode-profile"
OUT="$(mktemp -d)"
WORK="$OUT/pesto-virtual-display"
mkdir -p "$WORK/commands"

if pgrep -x Pesto >/dev/null 2>&1; then
  echo "virtual-display: quit any running Pesto instance first" >&2
  exit 1
fi

# Host wallpaper/Stage Manager toggles are opt-in (WITH_HOST_UI_TOGGLES=1) so normal runs leave MacBook settings untouched.
WITH_HOST_UI_TOGGLES="${WITH_HOST_UI_TOGGLES:-0}"
ORIG_WALLPAPER=""
ORIG_STAGE_MANAGER=""
if [ "$WITH_HOST_UI_TOGGLES" = "1" ]; then
  ORIG_WALLPAPER=$(osascript -e 'tell application "System Events" to get picture of desktop 1' 2>/dev/null || true)
  ORIG_STAGE_MANAGER=$(defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null || echo "__unset__")
fi

PID=""
restore_env() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  if [ "$WITH_HOST_UI_TOGGLES" = "1" ]; then
    if [ -n "$ORIG_WALLPAPER" ] && [ -e "$ORIG_WALLPAPER" ]; then
      osascript -e "tell application \"System Events\" to set picture of desktop 1 to POSIX file \"$ORIG_WALLPAPER\"" >/dev/null 2>&1 || true
    fi
    if [ "$ORIG_STAGE_MANAGER" = "__unset__" ]; then
      defaults delete com.apple.WindowManager GloballyEnabled >/dev/null 2>&1 || true
    else
      defaults write com.apple.WindowManager GloballyEnabled -bool "$ORIG_STAGE_MANAGER" >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$OUT"
}
trap restore_env EXIT ERR INT

if [[ "${PESTO_SKIP_PROFILE_BUILD:-0}" != "1" ]]; then
  make generate >/dev/null
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
    || { tail -20 "$OUT/build.log" >&2; echo "virtual-display: Profile build failed" >&2; exit 1; }
fi

APP="$DERIVED/Build/Products/Profile/Pesto.app"
BUNDLE_ENV="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$APP/Contents/Info.plist" | sed -n 's/^ *\(.*\) = \(.*\)$/\1=\2/p' | tr '\n' ' ')"
swiftc -O -parse-as-library -o "$OUT/VirtualDisplayTest" scripts/virtual-display/VirtualDisplayTest.swift

PESTO_UITEST_SESSION="virtual-display" PESTO_UITEST_DIR="$WORK" PESTO_UITEST_SEED="marketing" \
  PESTO_UITEST_ACCESSIBILITY=trusted PESTO_UITEST_DEFAULT_hasOnboarded=true \
  PESTO_UITEST_DEFAULT_shelfPosition=underNotch PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
  env $BUNDLE_ENV "$APP/Contents/MacOS/Pesto" -UITestMode >"$OUT/app.log" 2>&1 &
PID=$!

for _ in $(seq 1 300); do [ -f "$WORK/ready.json" ] && break; sleep 1; done
[ -f "$WORK/ready.json" ] || { echo "virtual-display: Pesto never became ready" >&2; exit 1; }

if [ "$WITH_HOST_UI_TOGGLES" = "1" ]; then
  defaults write com.apple.WindowManager GloballyEnabled -bool true
  sleep 0.5
fi
"$OUT/VirtualDisplayTest" "$WORK"
