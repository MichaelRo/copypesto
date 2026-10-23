#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds the Release configuration (hardened runtime on, optimised) without signing, signs it ad hoc with the runtime
# flag and checks that the bundle, Sparkle and the Control Center extension verify. The Debug build the gate otherwise
# uses has the hardened runtime off, so this is the only place a Release-only failure shows before a notarized build.
# It does not launch the result: an ad hoc signature cannot satisfy library validation for Sparkle.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DERIVED=.build/xcode-release
APP="$DERIVED/Build/Products/Release/Pesto.app"

make generate >/dev/null
xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
rm -rf "$APP"/Contents/PlugIns/*.xctest "$APP"/Contents/PlugIns/*.xctest.dSYM
codesign --force --deep --sign - --options runtime "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
flags="$(codesign -dvv "$APP" 2>&1 | grep -E '^CodeDirectory' || true)"
if [[ "$flags" != *runtime* ]]; then
  echo "check-release-build: the Release app is not signed with the hardened runtime: $flags" >&2
  exit 1
fi
hooks="$(/usr/libexec/PlistBuddy -c 'Print :PestoAllowsTestHooks' "$APP/Contents/Info.plist" 2>&1 || true)"
if [[ "$hooks" != "NO" ]]; then
  echo "check-release-build: the Release app allows test hooks (PestoAllowsTestHooks is '$hooks'), so -UITestMode would work in it" >&2
  exit 1
fi
[[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || { echo "check-release-build: Sparkle is not embedded" >&2; exit 1; }
echo "release build ok: $flags"
