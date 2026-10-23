#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds the Release configuration and signs it with the self-signed "Pesto Release" identity (`make
# setup-release-signing`), then packs the disk image and writes its SHA-256. Pesto 1.0 ships this way until a Developer ID
# exists (docs/release.md). No hardened runtime: Sparkle's library validation needs a Team ID this identity lacks.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

IDENTITY="${PESTO_RELEASE_IDENTITY:-Pesto Release}"
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  echo "release-unsigned: refusing to sign ad hoc: every update would be a new identity to the Keychain and Accessibility" >&2
  exit 1
fi
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "release-unsigned: no '$IDENTITY' signing identity. Run 'make setup-release-signing' once." >&2
  exit 1
fi

DERIVED=.build/xcode-release-unsigned
OUT=.build/release-unsigned
APP="$DERIVED/Build/Products/Release/Pesto.app"
ENTITLEMENTS=Sources/Resources/Pesto.entitlements

xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
rm -rf "$APP"/Contents/PlugIns/*.xctest "$APP"/Contents/PlugIns/*.xctest.dSYM

sign_one() {
  codesign --force --sign "$IDENTITY" --timestamp=none "$@"
}

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
[[ -d "$SPARKLE" ]] || { echo "release-unsigned: Sparkle is not embedded" >&2; exit 1; }
for piece in "$SPARKLE"/XPCServices/*.xpc "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
  [[ -e "$piece" ]] && sign_one "$piece"
done
sign_one "$APP/Contents/Frameworks/Sparkle.framework"
sign_one --entitlements Sources/Controls/PestoControls.entitlements "$APP/Contents/PlugIns/PestoControls.appex"
sign_one --entitlements "$ENTITLEMENTS" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
if codesign -dvv "$APP" 2>&1 | grep -E '^CodeDirectory' | grep -q runtime; then
  echo "release-unsigned: the app carries the hardened runtime, which Sparkle's library validation rejects" >&2
  exit 1
fi
hooks="$(/usr/libexec/PlistBuddy -c 'Print :PestoAllowsTestHooks' "$APP/Contents/Info.plist" 2>&1 || true)"
if [[ "$hooks" != "NO" ]]; then
  echo "release-unsigned: the app allows test hooks (PestoAllowsTestHooks is '$hooks')" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p "$OUT"
DMG="$OUT/Pesto-$VERSION.dmg"
rm -f "$OUT"/Pesto-*.dmg "$OUT"/Pesto-*.dmg.sha256
scripts/make-dmg.sh "$APP" "$DMG"
sign_one "$DMG"
(cd "$OUT" && shasum -a 256 "Pesto-$VERSION.dmg" > "Pesto-$VERSION.dmg.sha256")
echo "✓ $DMG"
cat "$DMG.sha256"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier|Authority|Signature|TeamIdentifier'
echo "Next: sign_update \"$DMG\" (Sparkle), then docs/release.md step 6."
