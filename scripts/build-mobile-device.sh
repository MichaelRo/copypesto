#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds PestoMobile for a connected iPhone or iPad without shell-quoting DEVICE names (apostrophes, spaces, quotes).
set -euo pipefail

dry_run="${PESTO_MOBILE_DRY_RUN:-0}"
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
  shift
fi

if [[ $# -ne 0 ]]; then
  echo "usage: scripts/build-mobile-device.sh [--dry-run]" >&2
  exit 2
fi

device="${DEVICE:-}"
device_id="${DEVICE_ID:-}"
team_id="${APPLE_TEAM_ID:-}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
scheme="${MOBILE_SCHEME:-PestoMobile}"
derived_data="${MOBILE_BUILD_DIR:-.build/xcode-ios-app}"

if [[ -z "$device_id" && -z "$device" ]]; then
  echo 'Name the device or pass its UDID: make build-mobile-device DEVICE="My iPhone" (or DEVICE_ID=<udid>)' >&2
  exit 1
fi

if [[ -z "$team_id" ]]; then
  echo "No team: install a Developer ID certificate or pass APPLE_TEAM_ID=..." >&2
  exit 1
fi

if [[ -n "$device_id" ]]; then
  destination="platform=iOS,id=${device_id}"
else
  destination="platform=iOS,name=${device}"
fi

cmd=(
  xcodebuild
  -project Pesto.xcodeproj
  -scheme "$scheme"
  -configuration Debug
  -derivedDataPath "$derived_data"
  -destination "$destination"
  -allowProvisioningUpdates
  "DEVELOPMENT_TEAM=${team_id}"
  CODE_SIGN_STYLE=Automatic
  build
)

if [[ "$dry_run" -eq 1 ]]; then
  printf '%s\n' "${cmd[@]}"
  exit 0
fi

export DEVELOPER_DIR="$developer_dir"
exec "${cmd[@]}"
