#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Writes exportOptions.plist with the team id filled in: render-export-options.sh <TEAM_ID> <output.plist> [PROFILE_NAME].
# With a profile name (the Developer ID provisioning profile for the sync key), the export signs manually with it.
# Stops when the team id is not 10 letters and digits, so an export never signs with a placeholder.
set -euo pipefail
team="${1:-}"
out="${2:-}"
profile="${3:-}"
if [[ ! "$team" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "render-export-options: '$team' is not a 10-character Team ID. Pass APPLE_TEAM_ID=XXXXXXXXXX." >&2
  exit 1
fi
[[ -n "$out" ]] || { echo "render-export-options: no output path" >&2; exit 1; }
cd "$(dirname "$0")/.."
cp exportOptions.plist "$out"
/usr/libexec/PlistBuddy -c "Set :teamID $team" "$out"
if [[ -n "$profile" ]]; then
  /usr/libexec/PlistBuddy -c "Set :signingStyle manual" "$out"
  /usr/libexec/PlistBuddy -c "Add :signingCertificate string 'Developer ID Application'" "$out"
  /usr/libexec/PlistBuddy -c "Add :provisioningProfiles dict" "$out"
  /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:net.copypesto.pesto string '$profile'" "$out"
fi
if grep -q 'PLACEHOLDER\|\$(' "$out"; then
  echo "render-export-options: a placeholder is left in $out" >&2
  exit 1
fi
