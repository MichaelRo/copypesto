#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Checks that an exported Pesto.app can keep the sync key in iCloud Keychain: check-sync-signing.sh <Pesto.app>.
# It needs the embedded Developer ID provisioning profile and the application-identifier entitlement, and the profile
# must list that identifier. It does not prove the Keychain item syncs; that takes two Macs (docs/release.md).
set -euo pipefail
app="${1:-}"
[[ -d "$app" ]] || { echo "check-sync-signing: pass the path of Pesto.app" >&2; exit 1; }
profile="$app/Contents/embedded.provisionprofile"
[[ -f "$profile" ]] || { echo "check-sync-signing: $profile is missing: the build was not signed with SYNC_PROFILE" >&2; exit 1; }
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)"
grep -q 'com.apple.application-identifier' <<< "$entitlements" || {
  echo "check-sync-signing: the app does not carry com.apple.application-identifier" >&2; exit 1; }
identifier="$(security cms -D -i "$profile" 2>/dev/null | plutil -extract Entitlements.com\\.apple\\.application-identifier raw - 2>/dev/null || true)"
[[ "$identifier" == *".net.copypesto.pesto" ]] || {
  echo "check-sync-signing: the profile's application identifier is '$identifier', not <team>.net.copypesto.pesto" >&2; exit 1; }
echo "sync signing ok: $identifier"
