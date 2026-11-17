#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Launch-at-login + VM reboot persistence test in an ephemeral Tart macOS VM.
# Requires a golden VM configured with autoLoginUser + /etc/kcpassword.
# Enables Launch at login, checks `sfltool dumpbtm`, cycles `tart stop` +
# `tart run`, asserts `pgrep -x Pesto` succeeds; toggles off, reboots again,
# and asserts `pgrep -x Pesto` fails.
#
# Usage: scripts/vm/vm-login-reboot.sh [path/to/Pesto.app-or-dmg]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/vm/vm-lib.sh
source "${SCRIPT_DIR}/vm-lib.sh"

APP_PKG="${1:-${PESTO_APP:-}}"
BASE_VM="${PESTO_VM_BASE:-pesto-macos15-golden}"

vm_require_tart
vm_install_cleanup_trap

CLONE_NAME="$(vm_unique_name "pesto-login")"
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
  mnt="$(mktemp -d /tmp/pesto-login-mnt.XXXXXX)"
  hdiutil attach "$pkg" -nobrowse -readonly -mountpoint "$mnt" -quiet
  ditto "$mnt/Pesto.app" /Applications/Pesto.app
  hdiutil detach "$mnt" -quiet || true
  rmdir "$mnt" 2>/dev/null || true
else
  ditto "$pkg" /Applications/Pesto.app
fi
REMOTE
fi

vm_log "Verifying autoLoginUser and /etc/kcpassword in golden VM..."
AUTO_LOGIN_OK="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
user="$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)"
if [[ -n "$user" && -f /etc/kcpassword ]]; then
  echo "ok:$user"
else
  echo "missing"
fi
REMOTE
)"
if [[ "$AUTO_LOGIN_OK" == ok:* ]]; then
  vm_pass "VM auto-login configured (${AUTO_LOGIN_OK#ok:})"
else
  vm_die "Golden VM missing autoLoginUser or /etc/kcpassword. See scripts/vm/README.md."
fi

toggle_launch_at_login() {
  local desired="$1"
  vm_ssh "$CLONE_NAME" bash -s "$desired" <<'REMOTE'
set -euo pipefail
desired="$1"
open /Applications/Pesto.app
for _ in $(seq 1 30); do
  if pgrep -x Pesto >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
sleep 1

osascript - "$desired" <<'OSA'
on run argv
  set desiredState to (item 1 of argv) as integer
  tell application "Pesto" to activate
  delay 0.5
  tell application "System Events"
    tell process "Pesto"
      keystroke "," using {command down}
      delay 0.8
      set cb to first checkbox of window 1 whose title contains "Launch at login" or name contains "Launch at login" or title contains "Open at login" or name contains "Open at login"
      set currentState to value of cb
      if currentState is not desiredState then
        click cb
        delay 0.5
      end if
    end tell
  end tell
end run
OSA
REMOTE
}

vm_log "Enabling Launch at login..."
toggle_launch_at_login 1

BTM_ON="$(vm_ssh "$CLONE_NAME" sfltool dumpbtm 2>/dev/null || true)"
if printf '%s' "$BTM_ON" | grep -q "net.copypesto.pesto"; then
  vm_pass "sfltool dumpbtm lists net.copypesto.pesto after enabling Launch at login"
else
  vm_fail "sfltool dumpbtm does not list net.copypesto.pesto"
fi

vm_log "Rebooting VM (tart stop + tart run) with Launch at login ON..."
vm_reboot "$CLONE_NAME"

if vm_wait_for 30 vm_ssh "$CLONE_NAME" pgrep -x Pesto >/dev/null 2>&1; then
  vm_pass "pgrep -x Pesto succeeded after reboot with Launch at login ON"
else
  vm_fail "pgrep -x Pesto failed after reboot with Launch at login ON"
fi

vm_log "Toggling Launch at login OFF..."
toggle_launch_at_login 0

vm_log "Rebooting VM (tart stop + tart run) with Launch at login OFF..."
vm_reboot "$CLONE_NAME"
sleep 8

if vm_ssh "$CLONE_NAME" pgrep -x Pesto >/dev/null 2>&1; then
  vm_fail "pgrep -x Pesto unexpectedly succeeded after reboot with Launch at login OFF"
else
  vm_pass "pgrep -x Pesto failed (not running) after reboot with Launch at login OFF"
fi

vm_finish
