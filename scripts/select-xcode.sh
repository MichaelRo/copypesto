#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Selects the newest Xcode installed on the machine (CI runners ship several). Prints the chosen path.
set -euo pipefail
newest="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)"
[[ -n "$newest" ]] || { echo "no Xcode found in /Applications" >&2; exit 1; }
sudo xcode-select -s "$newest"
echo "$newest"
xcodebuild -version
