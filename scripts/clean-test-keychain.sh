#!/bin/bash
# SPDX-License-Identifier: MIT
# Lists, and with --delete removes, the Keychain items that older Core test runs left in the login keychain: services named
# io.pesto.app.tests.<uuid> and io.pesto.tests.* (DeviceIdentityTests and LegacyAIKeyCleanupTests; they delete their own items now).
# Real items use the services net.copypesto.pesto, io.pesto.app and io.pesto.app.ai, which never match.
# Dry run by default; run `scripts/clean-test-keychain.sh --delete` by hand.
set -euo pipefail
services=$(security dump-keychain 2>/dev/null | sed -nE 's/.*"svce"<blob>="(io\.pesto\.(app\.)?tests\.[^"]*)".*/\1/p' | sort -u || true)
[ -n "$services" ] || { echo "no leftover test Keychain items"; exit 0; }
count=$(echo "$services" | wc -l | tr -d ' ')
if [ "${1:-}" != "--delete" ]; then
  echo "$count leftover test Keychain items, for example:"
  echo "$services" | sed -n '1,3p'
  echo "run with --delete to remove them"
  exit 0
fi
echo "$services" | while read -r service; do security delete-generic-password -s "$service" >/dev/null 2>&1 || true; done
echo "removed $count leftover test Keychain items"
