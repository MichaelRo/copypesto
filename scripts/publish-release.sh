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

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .build/xcode/export/Pesto.app/Contents/Info.plist 2>/dev/null || grep 'MARKETING_VERSION:' Pesto.yml | head -1 | awk '{print $2}' | tr -d '"')
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' .build/xcode/export/Pesto.app/Contents/Info.plist 2>/dev/null || grep 'CURRENT_PROJECT_VERSION:' Pesto.yml | head -1 | awk '{print $2}' | tr -d '"')
DMG=".build/xcode/export/Pesto-${VERSION}.dmg"
SHA="${DMG}.sha256"

if [ ! -f "$DMG" ]; then
    echo "Error: Release DMG not found at $DMG" >&2
    exit 1
fi

if [ ! -f "$SHA" ]; then
    echo "==> Generating SHA-256 for release DMG..."
    (cd ".build/xcode/export" && shasum -a 256 "Pesto-${VERSION}.dmg" > "Pesto-${VERSION}.dmg.sha256")
fi

echo "==> Release artifact created: $DMG"
cat "$SHA"

echo ""
echo "================================================================="
echo "  Release Pesto v${VERSION} (${BUILD}) ready!"
echo "  Next steps (docs/release.md):"
echo "  1. Sign DMG with Sparkle: sign_update \"$DMG\""
echo "  2. Publish the release entry (docs/release.md, step 4)"
echo "  3. Create GitHub Release and upload $DMG and $SHA"
echo "================================================================="
