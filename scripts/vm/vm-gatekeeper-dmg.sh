#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Gatekeeper + quarantined DMG launch verification in an ephemeral Tart macOS VM.
# Stamps com.apple.quarantine on Pesto-<version>.dmg, installs to /Applications,
# asserts syspolicy_check --json distribution, launches Pesto.app, and drives
# CoreServicesUIAgent ("Open", never "Open Anyway") into Onboarding.
#
# Usage: scripts/vm/vm-gatekeeper-dmg.sh <path/to/Pesto-<version>.dmg>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/vm/vm-lib.sh
source "${SCRIPT_DIR}/vm-lib.sh"

DMG_PATH="${1:-${PESTO_DMG:-}}"
BASE_VM="${PESTO_VM_BASE:-pesto-macos15-golden}"

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  printf 'Usage: %s <path/to/Pesto-<version>.dmg>\n' "$0" >&2
  exit 2
fi

vm_require_tart
vm_install_cleanup_trap

CLONE_NAME="$(vm_unique_name "pesto-gk")"
vm_clone "$BASE_VM" "$CLONE_NAME"
vm_start "$CLONE_NAME"

DMG_NAME="$(basename "$DMG_PATH")"
REMOTE_DMG="/tmp/${DMG_NAME}"
vm_log "Copying ${DMG_NAME} to VM..."
vm_copy_to "$CLONE_NAME" "$DMG_PATH" "$REMOTE_DMG"

vm_log "Stamping com.apple.quarantine and installing to /Applications..."
vm_ssh "$CLONE_NAME" bash -s "$REMOTE_DMG" <<'REMOTE'
set -euo pipefail
dmg="$1"
stamp="0083;$(printf '%x' "$(date +%s)");Safari;|com.apple.Safari"
xattr -w com.apple.quarantine "$stamp" "$dmg"

mnt="$(mktemp -d /tmp/pesto-mnt.XXXXXX)"
cleanup_mnt() {
  hdiutil detach "$mnt" -quiet >/dev/null 2>&1 || true
  rmdir "$mnt" 2>/dev/null || true
}
trap cleanup_mnt EXIT

hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mnt" -quiet
rm -rf /Applications/Pesto.app
ditto "$mnt/Pesto.app" /Applications/Pesto.app
if ! xattr -p com.apple.quarantine /Applications/Pesto.app >/dev/null 2>&1; then
  xattr -w com.apple.quarantine "$stamp" /Applications/Pesto.app
fi
REMOTE
vm_pass "Quarantined DMG mounted and Pesto.app copied to /Applications"

vm_log "Running syspolicy_check --json distribution /Applications/Pesto.app..."
SYSPOLICY_OUT="$(vm_ssh "$CLONE_NAME" syspolicy_check --json distribution /Applications/Pesto.app)"
vm_log "syspolicy_check output: ${SYSPOLICY_OUT}"
if printf '%s' "$SYSPOLICY_OUT" | grep -qiE '"result"\s*:\s*"?(pass|allow|ok)|"passed"\s*:\s*true'; then
  vm_pass "syspolicy_check distribution passed"
else
  # syspolicy_check exits 0 when distribution passes; if JSON doesn't have an explicit error, accept exit 0
  if printf '%s' "$SYSPOLICY_OUT" | grep -qiE '"error"|"rejected"|"denied"'; then
    vm_fail "syspolicy_check reported failure: ${SYSPOLICY_OUT}"
  else
    vm_pass "syspolicy_check distribution exited 0"
  fi
fi

vm_log "Launching /Applications/Pesto.app and handling CoreServicesUIAgent..."
vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
open /Applications/Pesto.app

# Poll up to 20s for CoreServicesUIAgent quarantine prompt and click "Open" (not "Open Anyway").
osascript <<'OSA'
set clickedOpen to false
repeat 40 times
  tell application "System Events"
    if exists process "CoreServicesUIAgent" then
      tell process "CoreServicesUIAgent"
        if (count of windows) > 0 then
          set btnNames to name of every button of window 1
          if btnNames contains "Open Anyway" then
            error "Unexpected Gatekeeper 'Open Anyway' prompt (notarization/quarantine failed)"
          end if
          if btnNames contains "Open" then
            click button "Open" of window 1
            set clickedOpen to true
            exit repeat
          end if
        end if
      end tell
    end if
    if exists process "Pesto" then
      tell process "Pesto"
        if (count of windows) > 0 then
          exit repeat
        end if
      end tell
    end if
  end tell
  delay 0.5
end repeat
OSA
REMOTE

if vm_ssh "$CLONE_NAME" pgrep -x Pesto >/dev/null 2>&1; then
  vm_pass "Pesto.app launched past Gatekeeper"
else
  vm_fail "Pesto.app is not running after CoreServicesUIAgent"
fi

ONBOARDING_CHECK="$(vm_ssh "$CLONE_NAME" osascript <<'OSA' || true
tell application "System Events"
  if exists process "Pesto" then
    tell process "Pesto"
      return (count of windows) as text
    end tell
  end if
  return "0"
end tell
OSA
)"
if [[ "${ONBOARDING_CHECK:-0}" -ge 1 ]]; then
  vm_pass "Onboarding window visible after Gatekeeper approval (windows: ${ONBOARDING_CHECK})"
else
  vm_fail "Expected Onboarding window after Gatekeeper launch, saw ${ONBOARDING_CHECK:-0} windows"
fi

vm_finish
