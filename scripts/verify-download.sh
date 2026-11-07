#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Checks a downloaded Pesto disk image the way a person would, in seconds: its SHA-256 against the .sha256 file beside it
# (or a hash given as the second argument), the code signature and its Team ID, Gatekeeper's verdict, and the stapled
# notarization tickets of the app and the image. Run by `make verify-download DMG=~/Downloads/Pesto-<version>.dmg`.
#   scripts/verify-download.sh <dmg> [expected-sha256]
# Exit codes: 0 everything holds, 1 a check failed, 2 usage.
set -uo pipefail

TEAM_ID="${PESTO_TEAM_ID:-NBD55BZ3N4}"
dmg="${1:-}"
[ -n "$dmg" ] && [ -f "$dmg" ] || { echo "usage: verify-download.sh <Pesto-version.dmg> [expected-sha256]" >&2; exit 2; }

failed=0
check() {
  local label=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $label"; else echo "FAIL  $label"; failed=1; fi
}

actual=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
expected="${2:-}"
if [ -z "$expected" ] && [ -f "$dmg.sha256" ]; then expected=$(cut -d' ' -f1 "$dmg.sha256"); fi
expected=$(printf '%s' "$expected" | tr 'A-F' 'a-f')
if [ -z "$expected" ]; then
  echo "note  no expected hash given and no $(basename "$dmg").sha256 beside it: the hash is $actual"
elif [ "$actual" = "$expected" ]; then
  echo "ok    SHA-256 $actual"
else
  echo "FAIL  SHA-256 is $actual, expected $expected"
  exit 1
fi

mount_point=$(mktemp -d)
cleanup() { hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 || true; rmdir "$mount_point" 2>/dev/null || true; }
trap cleanup EXIT
if ! hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_point" -quiet >/dev/null 2>&1; then
  echo "FAIL  $(basename "$dmg") does not open as a disk image"
  exit 1
fi
app="$mount_point/Pesto.app"
[ -d "$app" ] || { echo "FAIL  no Pesto.app in the image"; exit 1; }

check "code signature is valid (deep, strict)" codesign --verify --deep --strict "$app"
if codesign -dvvv "$app" 2>&1 | grep "TeamIdentifier=$TEAM_ID" >/dev/null; then
  echo "ok    Team ID $TEAM_ID"
else
  echo "FAIL  Team ID is not $TEAM_ID"; failed=1
fi
if spctl --assess --type execute -vv "$app" 2>&1 | grep "Notarized Developer ID" >/dev/null; then
  echo "ok    Gatekeeper: Notarized Developer ID"
else
  echo "FAIL  Gatekeeper does not say Notarized Developer ID"; failed=1
fi
check "app notarization ticket is stapled" xcrun stapler validate "$app"
check "disk image notarization ticket is stapled" xcrun stapler validate "$dmg"

[ "$failed" = 0 ] && echo "all checks passed" || echo "some checks failed"
exit "$failed"
