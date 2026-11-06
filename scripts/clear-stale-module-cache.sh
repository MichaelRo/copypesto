#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Clears the precompiled module caches in .build when the package pins changed (Pesto.resolved), run by `make generate`.
# A cache built before a package bump outlives the package: after Sparkle 2.10.1 `make install` and both benches failed
# with "Sparkle.framework/Headers/SUAppcastItem.h has been modified since the module file ... was built". Only the module
# caches go (the compiler rebuilds them in seconds), never the build's objects. Someone who runs the app, or installs it
# from the DMG, has no build folder and never meets this.
set -euo pipefail
cd "$(dirname "$0")/.."

stamp=.build/package-pins.sha
pins=$(shasum -a 256 Pesto.resolved | cut -d' ' -f1)
if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$pins" ]; then
  exit 0
fi

for folder in .build/*/Build/Intermediates.noindex; do
  [ -d "$folder" ] && rm -rf "$folder/SwiftExplicitPrecompiledModules"
done
for folder in .build/*/ModuleCache.noindex; do
  [ -d "$folder" ] && rm -rf "$folder"
done
mkdir -p .build
echo "$pins" > "$stamp"
exit 0
