#!/bin/bash
# SPDX-License-Identifier: MIT
# Removes the throwaway preferences files that Pesto's own test suites leave in ~/Library/Preferences, and nothing else:
# io.pesto.tests.*, io.pesto.uitest.*, pesto-test-*, nsfw-mode-<UUID>, rules-test-<UUID> and test-<UUID> (the names the tests give their domains). Real
# settings live in net.copypesto.pesto.plist and io.pesto.app.plist, which never match. Run it by hand;
# `--dry-run` lists what would go. Tests no longer create these files (`ThrowawayDefaults`), so this clears old ones.
set -euo pipefail
DIR="$HOME/Library/Preferences"
UUID='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
found=$(cd "$DIR" && ls 2>/dev/null | grep -E "^(io\.pesto\.tests\.|io\.pesto\.uitest\.|pesto-test-).*\.plist$|^(test|nsfw-mode|rules-test)-${UUID}\.plist$" || true)
[ -n "$found" ] || { echo "no leftover test preferences"; exit 0; }
count=$(echo "$found" | wc -l | tr -d ' ')
if [ "${1:-}" = "--dry-run" ]; then
  echo "$count leftover test preference files, for example:"
  echo "$found" | head -5
  exit 0
fi
(cd "$DIR" && echo "$found" | xargs rm -f)
echo "removed $count leftover test preference files"
