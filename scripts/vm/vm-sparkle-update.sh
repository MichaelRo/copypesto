#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Sparkle 2 Developer ID update verification in an ephemeral Tart macOS VM.
# Installs a previous Developer ID release, seeds history + Accessibility,
# overrides SUFeedURL to a loopback 127.0.0.1 appcast.xml, runs Sparkle 2
# `sparkle --check-immediately --grant-automatic-checks`, and asserts:
#   1. CFBundleVersion bumped
#   2. Zero SecurityAgent Keychain prompts
#   3. Preserved clipboard history and blobKey
#   4. AXIsProcessTrusted() == true after update
#
# Usage: scripts/vm/vm-sparkle-update.sh <prev-Pesto.app-or-dmg> <update-archive> <appcast.xml> [sparkle-cli]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/vm/vm-lib.sh
source "${SCRIPT_DIR}/vm-lib.sh"

PREV_PKG="${1:-${PESTO_PREV_APP:-}}"
UPDATE_ARCHIVE="${2:-${PESTO_UPDATE_ARCHIVE:-}}"
APPCAST_XML="${3:-${PESTO_APPCAST_XML:-}}"
SPARKLE_CLI="${4:-${PESTO_SPARKLE_CLI:-}}"
BASE_VM="${PESTO_VM_BASE:-pesto-macos15-sip-off}"
FEED_PORT="${PESTO_FEED_PORT:-18421}"

if [[ -z "$PREV_PKG" || -z "$UPDATE_ARCHIVE" || -z "$APPCAST_XML" ]]; then
  printf 'Usage: %s <prev-Pesto.app-or-dmg> <update-archive> <appcast.xml> [sparkle-cli]\n' "$0" >&2
  exit 2
fi
[[ -e "$PREV_PKG" ]] || vm_die "Previous package not found: $PREV_PKG"
[[ -f "$UPDATE_ARCHIVE" ]] || vm_die "Update archive not found: $UPDATE_ARCHIVE"
[[ -f "$APPCAST_XML" ]] || vm_die "Appcast XML not found: $APPCAST_XML"

vm_require_tart
vm_install_cleanup_trap

CLONE_NAME="$(vm_unique_name "pesto-sparkle")"
vm_clone "$BASE_VM" "$CLONE_NAME"
vm_start "$CLONE_NAME"

vm_log "Copying previous release, update archive, and appcast.xml to VM..."
vm_ssh "$CLONE_NAME" mkdir -p /tmp/sparkle-feed /tmp/sparkle-prev
vm_copy_to "$CLONE_NAME" "$PREV_PKG" "/tmp/sparkle-prev/$(basename "$PREV_PKG")"
vm_copy_to "$CLONE_NAME" "$UPDATE_ARCHIVE" "/tmp/sparkle-feed/$(basename "$UPDATE_ARCHIVE")"
vm_copy_to "$CLONE_NAME" "$APPCAST_XML" "/tmp/sparkle-feed/appcast.xml"
if [[ -n "$SPARKLE_CLI" && -e "$SPARKLE_CLI" ]]; then
  vm_copy_to "$CLONE_NAME" "$SPARKLE_CLI" "/tmp/sparkle-cli"
fi

vm_log "Installing previous release, granting Accessibility, and seeding history..."
PREV_VERSION="$(vm_ssh "$CLONE_NAME" bash -s "/tmp/sparkle-prev/$(basename "$PREV_PKG")" <<'REMOTE'
set -euo pipefail
pkg="$1"
rm -rf /Applications/Pesto.app
if [[ "$pkg" == *.dmg ]]; then
  mnt="$(mktemp -d /tmp/pesto-prev-mnt.XXXXXX)"
  hdiutil attach "$pkg" -nobrowse -readonly -mountpoint "$mnt" -quiet
  ditto "$mnt/Pesto.app" /Applications/Pesto.app
  hdiutil detach "$mnt" -quiet || true
  rmdir "$mnt" 2>/dev/null || true
else
  ditto "$pkg" /Applications/Pesto.app
fi

# Grant Accessibility in TCC.db (requires SIP-disabled golden VM)
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAccessibility', 'net.copypesto.pesto', 0, 2, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, strftime('%s','now'));"

/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/Pesto.app/Contents/Info.plist
REMOTE
)"
vm_log "Installed previous build version: ${PREV_VERSION}"

vm_log "Launching previous build to seed clipboard history..."
vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
open /Applications/Pesto.app
for _ in $(seq 1 30); do
  if pgrep -x Pesto >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
sleep 2

printf 'sparkle-seed-clip-%s' "$(date +%s)" | pbcopy
sleep 2
REMOTE

# Verify AXIsProcessTrusted() == true before update
AX_BEFORE="$(vm_ssh "$CLONE_NAME" swift -e 'import ApplicationServices; print(AXIsProcessTrusted())' 2>/dev/null || true)"
vm_log "AXIsProcessTrusted before update (harness context): ${AX_BEFORE}"

vm_log "Starting loopback appcast server on 127.0.0.1:${FEED_PORT} and running Sparkle 2 CLI..."
UPDATE_RESULT="$(vm_ssh "$CLONE_NAME" bash -s "$FEED_PORT" <<'REMOTE'
set -euo pipefail
port="$1"

defaults write net.copypesto.pesto SUFeedURL "http://127.0.0.1:${port}/appcast.xml"

python3 -m http.server "$port" --bind 127.0.0.1 --directory /tmp/sparkle-feed >/tmp/sparkle-http.log 2>&1 &
http_pid=$!

sec_agent_seen=0
watch_sec_agent() {
  while kill -0 "$http_pid" 2>/dev/null; do
    if pgrep -x SecurityAgent >/dev/null 2>&1; then
      echo "1" > /tmp/sparkle-sec-agent-seen
      break
    fi
    sleep 0.25
  done
}
rm -f /tmp/sparkle-sec-agent-seen
watch_sec_agent &
watch_pid=$!

cleanup_srv() {
  kill "$http_pid" "$watch_pid" >/dev/null 2>&1 || true
}
trap cleanup_srv EXIT

sparkle_bin="/tmp/sparkle-cli"
if [[ ! -x "$sparkle_bin" ]]; then
  sparkle_bin="$(command -v sparkle || true)"
fi
if [[ -z "$sparkle_bin" ]]; then
  sparkle_bin="/Applications/Pesto.app/Contents/Frameworks/Sparkle.framework/Versions/B/Resources/Autoupdate.app/Contents/MacOS/Autoupdate"
fi

"$sparkle_bin" /Applications/Pesto.app --check-immediately --grant-automatic-checks >/tmp/sparkle-cli.log 2>&1 || true

# Wait up to 60s for Sparkle to finish replacing /Applications/Pesto.app
for _ in $(seq 1 60); do
  if ! pgrep -x Autoupdate >/dev/null 2>&1 && ! pgrep -x Updater >/dev/null 2>&1; then
    sleep 1
    break
  fi
  sleep 1
done

new_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/Pesto.app/Contents/Info.plist)"
if [[ -f /tmp/sparkle-sec-agent-seen ]]; then
  sec_agent_seen=1
fi
printf '%s|%s\n' "$new_ver" "$sec_agent_seen"
REMOTE
)"

NEW_VERSION="${UPDATE_RESULT%%|*}"
SEC_AGENT_SEEN="${UPDATE_RESULT##*|}"

if [[ -n "$NEW_VERSION" && "$NEW_VERSION" != "$PREV_VERSION" ]]; then
  vm_pass "Sparkle bumped CFBundleVersion: ${PREV_VERSION} -> ${NEW_VERSION}"
else
  vm_fail "Expected CFBundleVersion to bump from ${PREV_VERSION}, got '${NEW_VERSION}'"
fi

if [[ "$SEC_AGENT_SEEN" == "0" ]]; then
  vm_pass "Zero SecurityAgent Keychain prompts during Sparkle update"
else
  vm_fail "SecurityAgent Keychain prompt appeared during Sparkle update"
fi

vm_log "Verifying preserved history and AXIsProcessTrusted() after update..."
POST_CHECKS="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
open /Applications/Pesto.app
sleep 3

has_key=0
if security find-generic-password -s "net.copypesto.pesto" -a "net.copypesto.pesto.blobKey" >/dev/null 2>&1; then
  has_key=1
fi

store_rows=0
store_db="$(find "$HOME/Library/Application Support" -maxdepth 3 -name 'default.store' 2>/dev/null | head -n 1 || true)"
if [[ -n "$store_db" ]]; then
  store_rows="$(sqlite3 "$store_db" "SELECT count(*) FROM ZCLIPBOARDITEM;" 2>/dev/null || echo "0")"
fi

ax_ok="$(osascript -l JavaScript -e 'ObjC.import("ApplicationServices"); $.AXIsProcessTrusted()' 2>/dev/null || echo "false")"
printf '%s|%s|%s\n' "$has_key" "$store_rows" "$ax_ok"
REMOTE
)"

IFS='|' read -r HAS_KEY STORE_ROWS AX_OK <<<"$POST_CHECKS"

if [[ "$HAS_KEY" == "1" && "${STORE_ROWS:-0}" -ge 1 ]]; then
  vm_pass "Clipboard history preserved across update (rows=${STORE_ROWS}, blobKey present)"
else
  vm_fail "History not preserved after update (has_key=${HAS_KEY}, store_rows=${STORE_ROWS})"
fi

if [[ "$AX_OK" == "true" ]]; then
  vm_pass "AXIsProcessTrusted() == true after update"
else
  vm_fail "AXIsProcessTrusted() returned '${AX_OK}' after update"
fi

vm_finish
