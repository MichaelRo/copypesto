#!/bin/bash
# SPDX-License-Identifier: MIT
# Pesto — Release publishing pipeline helper.
# Builds the notarized DMG and prints the next steps for the release.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Running release checks..."
make release-check

echo "==> Building notarized release DMG..."
make dmg

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Resources/Info.plist)
DMG=".build/xcode/export/Pesto-${VERSION}.dmg"

if [ ! -f "$DMG" ]; then
    echo "Error: Release DMG not found at $DMG" >&2
    exit 1
fi

echo "==> Release artifact created: $DMG"

echo ""
echo "================================================================="
echo "  Release Pesto v${VERSION} (${BUILD}) ready!"
echo "  Next steps (docs/release.md):"
echo "  1. Sign DMG with Sparkle: sign_update \"$DMG\""
echo "  2. Publish the release entry (docs/release.md, step 4)"
echo "  3. Create GitHub Release and upload $DMG"
echo "================================================================="
