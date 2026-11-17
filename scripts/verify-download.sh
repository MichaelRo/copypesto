#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Checks a downloaded Pesto disk image the way a person would, in seconds: its SHA-256 against the .sha256 file beside it
# (or a hash given as the second argument), the code signature and its Team ID, Gatekeeper's verdict, and the stapled
# notarization tickets of the app and the image. Run by `make verify-download DMG=~/Downloads/Pesto-<version>.dmg`.
#   scripts/verify-download.sh [--check-live <version>] <dmg> [expected-sha256]
# Exit codes: 0 everything holds, 1 a check failed, 2 usage.
set -uo pipefail

TEAM_ID="${PESTO_TEAM_ID:-NBD55BZ3N4}"
LIVE_VERSION=""
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check-live)
      LIVE_VERSION="${2:-}"
      [ -n "$LIVE_VERSION" ] || { echo "usage: verify-download.sh [--check-live <version>] <Pesto-version.dmg> [expected-sha256]" >&2; exit 2; }
      shift 2
      ;;
    --check-live=*)
      LIVE_VERSION="${1#*=}"
      [ -n "$LIVE_VERSION" ] || { echo "usage: verify-download.sh [--check-live <version>] <Pesto-version.dmg> [expected-sha256]" >&2; exit 2; }
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

dmg="${POSITIONAL[0]:-}"
expected="${POSITIONAL[1]:-}"

if [ -z "$LIVE_VERSION" ]; then
  [ -n "$dmg" ] && [ -f "$dmg" ] || { echo "usage: verify-download.sh [--check-live <version>] <Pesto-version.dmg> [expected-sha256]" >&2; exit 2; }
fi

failed=0
check() {
  local label=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $label"; else echo "FAIL  $label"; failed=1; fi
}

actual=""
if [ -n "$dmg" ] && [ -f "$dmg" ]; then
  actual=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
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
fi

if [ -n "$LIVE_VERSION" ]; then
  tag="v${LIVE_VERSION#v}"
  gh_body=$(curl -fsSL --max-time 30 "https://api.github.com/repos/MichaelRo/copypesto/releases/tags/${tag}" 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("body",""))' 2>/dev/null || true)
  gh_sha=$(printf '%s\n' "$gh_body" | grep -Eio '[a-f0-9]{64}' | head -1 | tr 'A-F' 'a-f' || true)
  if [ -z "$gh_sha" ]; then
    echo "FAIL  could not find a SHA-256 in GitHub release ${tag} body"
    failed=1
  else
    echo "ok    GitHub release ${tag} SHA-256: $gh_sha"
  fi

  web_html=$(curl -fsSL --max-time 30 "https://copypesto.net/download/" 2>/dev/null || curl -fsSL --max-time 30 "https://copypesto.net/download" 2>/dev/null || true)
  web_sha=$(printf '%s\n' "$web_html" | grep -Eio '[a-f0-9]{64}' | head -1 | tr 'A-F' 'a-f' || true)
  if [ -z "$web_sha" ]; then
    echo "FAIL  could not find a SHA-256 on copypesto.net/download"
    failed=1
  else
    echo "ok    copypesto.net/download SHA-256: $web_sha"
  fi

  if [ -n "$gh_sha" ] && [ -n "$web_sha" ]; then
    if [ "$gh_sha" = "$web_sha" ]; then
      echo "ok    GitHub release and copypesto.net/download SHA-256 match"
    else
      echo "FAIL  GitHub release SHA-256 ($gh_sha) != copypesto.net/download SHA-256 ($web_sha)"
      failed=1
    fi
  fi

  ref_sha="${actual:-$expected}"
  if [ -n "$ref_sha" ] && [ -n "$gh_sha" ] && [ "$ref_sha" != "$gh_sha" ]; then
    echo "FAIL  local SHA-256 ($ref_sha) != GitHub release SHA-256 ($gh_sha)"
    failed=1
  fi
  if [ -n "$ref_sha" ] && [ -n "$web_sha" ] && [ "$ref_sha" != "$web_sha" ]; then
    echo "FAIL  local SHA-256 ($ref_sha) != copypesto.net/download SHA-256 ($web_sha)"
    failed=1
  fi
  [ -n "$dmg" ] && [ -f "$dmg" ] || { [ "$failed" = 0 ] && echo "all live checks passed" || echo "some live checks failed"; exit "$failed"; }
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
