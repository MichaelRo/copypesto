#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Installs the pinned SwiftFormat, SwiftLint and XcodeGen into .build/tools and prints the directory to put on PATH:
#   export PATH="$(scripts/install-tools.sh):$PATH"
# Used by CI. Locally, any install at the pinned versions (see scripts/tool-versions.env) works too. Every download is
# checked against the SHA-256 in tool-versions.env before it is unpacked.

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/tool-versions.env

TOOLS=".build/tools"
mkdir -p "$TOOLS"

fetch() { # fetch <url> <sha256> <zip> <destination>
  curl -fsSL "$1" -o "$3"
  local actual
  actual="$(shasum -a 256 "$3" | cut -d' ' -f1)"
  if [[ "$actual" != "$2" ]]; then
    echo "install-tools: $1 has SHA-256 $actual, expected $2" >&2
    rm -f "$3"
    exit 1
  fi
  mkdir -p "$4"
  unzip -qo "$3" -d "$4"
}

if [[ ! -x "$TOOLS/swiftformat-$SWIFTFORMAT_VERSION/swiftformat" ]]; then
  fetch "https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip" \
    "$SWIFTFORMAT_SHA256" "$TOOLS/swiftformat.zip" "$TOOLS/swiftformat-$SWIFTFORMAT_VERSION"
fi
if [[ ! -x "$TOOLS/swiftlint-$SWIFTLINT_VERSION/swiftlint" ]]; then
  fetch "https://github.com/realm/SwiftLint/releases/download/$SWIFTLINT_VERSION/portable_swiftlint.zip" \
    "$SWIFTLINT_SHA256" "$TOOLS/swiftlint.zip" "$TOOLS/swiftlint-$SWIFTLINT_VERSION"
fi
if [[ ! -x "$TOOLS/xcodegen-$XCODEGEN_VERSION/xcodegen/bin/xcodegen" ]]; then
  fetch "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip" \
    "$XCODEGEN_SHA256" "$TOOLS/xcodegen.zip" "$TOOLS/xcodegen-$XCODEGEN_VERSION"
fi
chmod +x "$TOOLS/swiftformat-$SWIFTFORMAT_VERSION/swiftformat" "$TOOLS/swiftlint-$SWIFTLINT_VERSION/swiftlint" \
  "$TOOLS/xcodegen-$XCODEGEN_VERSION/xcodegen/bin/xcodegen"

# One directory holding all three, so a single PATH entry is enough. XcodeGen finds its setting presets next to its
# own binary, so it is started through a wrapper instead of a symlink.
mkdir -p "$TOOLS/bin"
ln -sf "../swiftformat-$SWIFTFORMAT_VERSION/swiftformat" "$TOOLS/bin/swiftformat"
ln -sf "../swiftlint-$SWIFTLINT_VERSION/swiftlint" "$TOOLS/bin/swiftlint"
printf '#!/bin/sh\nexec "%s/%s/xcodegen-%s/xcodegen/bin/xcodegen" "$@"\n' "$(pwd)" "$TOOLS" "$XCODEGEN_VERSION" \
  >"$TOOLS/bin/xcodegen"
chmod +x "$TOOLS/bin/xcodegen"
echo "$(pwd)/$TOOLS/bin"
