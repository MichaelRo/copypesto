#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Keychain blobKey loss & recovery verification in an ephemeral Tart macOS VM.
# Launches Pesto.app, ingests a clip, quits, deletes net.copypesto.pesto.blobKey,
# relaunches, asserts "Pesto can’t unlock your clipboard history" alert appears,
# asserts `security find-generic-password` stays empty (exit 44) until
# "Start With Empty History" is clicked, then clicks it and verifies recovery.
#
# Usage: scripts/vm/vm-keychain-loss.sh [path/to/Pesto.app-or-dmg]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/vm/vm-lib.sh
source "${SCRIPT_DIR}/vm-lib.sh"

APP_PKG="${1:-${PESTO_APP:-}}"
BASE_VM="${PESTO_VM_BASE:-pesto-macos15-golden}"

vm_require_tart
vm_install_cleanup_trap

CLONE_NAME="$(vm_unique_name "pesto-keychain")"
vm_clone "$BASE_VM" "$CLONE_NAME"
vm_start "$CLONE_NAME"

if [[ -n "$APP_PKG" ]]; then
  [[ -e "$APP_PKG" ]] || vm_die "Package not found: $APP_PKG"
  vm_copy_to "$CLONE_NAME" "$APP_PKG" "/tmp/$(basename "$APP_PKG")"
  vm_ssh "$CLONE_NAME" bash -s "/tmp/$(basename "$APP_PKG")" <<'REMOTE'
set -euo pipefail
pkg="$1"
rm -rf /Applications/Pesto.app
if [[ "$pkg" == *.dmg ]]; then
  mnt="$(mktemp -d /tmp/pesto-kc-mnt.XXXXXX)"
  hdiutil attach "$pkg" -nobrowse -readonly -mountpoint "$mnt" -quiet
  ditto "$mnt/Pesto.app" /Applications/Pesto.app
  hdiutil detach "$mnt" -quiet || true
  rmdir "$mnt" 2>/dev/null || true
else
  ditto "$pkg" /Applications/Pesto.app
fi
REMOTE
fi

vm_log "Launching Pesto.app and ingesting a clip..."
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

printf 'keychain-loss-seed-%s' "$(date +%s)" | pbcopy
sleep 2

osascript -e 'tell application "Pesto" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  if ! pgrep -x Pesto >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
pkill -x Pesto >/dev/null 2>&1 || true
REMOTE

vm_log "Deleting blobKey from Keychain..."
vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
security delete-generic-password -s "net.copypesto.pesto" -a "net.copypesto.pesto.blobKey" >/dev/null
REMOTE
vm_pass "Deleted net.copypesto.pesto.blobKey from Keychain"

vm_log "Relaunching Pesto.app and inspecting recovery alert..."
ALERT_RESULT="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
open /Applications/Pesto.app

alert_text=""
for _ in $(seq 1 30); do
  alert_text="$(osascript <<'OSA' || true
tell application "System Events"
  if exists process "Pesto" then
    tell process "Pesto"
      repeat with w in windows
        set texts to value of every static text of w
        repeat with t in texts
          if (t as text) contains "unlock your clipboard history" then
            return t as text
          end if
        end repeat
      end repeat
    end tell
  end if
end tell
return ""
OSA
)"
  if [[ -n "$alert_text" ]]; then
    break
  fi
  sleep 0.5
done

rc=0
security find-generic-password -s "net.copypesto.pesto" -a "net.copypesto.pesto.blobKey" >/dev/null 2>&1 || rc=$?
printf '%s|%s\n' "$alert_text" "$rc"
REMOTE
)"

ALERT_TEXT="${ALERT_RESULT%%|*}"
FIND_RC="${ALERT_RESULT##*|}"

if [[ "$ALERT_TEXT" == *"unlock your clipboard history"* ]]; then
  vm_pass "Alert appeared: ${ALERT_TEXT}"
else
  vm_fail "Expected 'Pesto can’t unlock your clipboard history' alert, got '${ALERT_TEXT}'"
fi

if [[ "$FIND_RC" == "44" ]]; then
  vm_pass "Keychain blobKey stays empty (exit 44) before clicking 'Start With Empty History'"
else
  vm_fail "Expected security find-generic-password exit 44 before recovery, got ${FIND_RC}"
fi

vm_log "Clicking 'Start With Empty History' and verifying new blobKey..."
RECOVERY_RC="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
osascript <<'OSA'
tell application "System Events"
  tell process "Pesto"
    repeat with w in windows
      if exists button "Start With Empty History" of w then
        click button "Start With Empty History" of w
        exit repeat
      end if
    end repeat
  end tell
end tell
OSA
sleep 2
rc=0
security find-generic-password -s "net.copypesto.pesto" -a "net.copypesto.pesto.blobKey" >/dev/null 2>&1 || rc=$?
echo "$rc"
REMOTE
)"

if [[ "$RECOVERY_RC" == "0" ]]; then
  vm_pass "New blobKey created after clicking 'Start With Empty History'"
else
  vm_fail "Expected new blobKey after clicking 'Start With Empty History', got exit ${RECOVERY_RC}"
fi

vm_finish
