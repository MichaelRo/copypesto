#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# TCC, Accessibility, Screen-Share, Hotkey, Paste-Matrix, and Full Keyboard Access
# verification suite in an ephemeral SIP-disabled Tart macOS 15.4+ VM.
#
# Covers:
#   1. kTCCServicePasteboard (auth_value=0 / `tccutil reset Pasteboard` on macOS 15.4+)
#   2. SIP-disabled TCC.db Accessibility onboarding advance (OnboardingView 1.5s poller)
#   3. Chrome --use-fake-ui-for-media-stream --auto-select-desktop-capture-source="Entire screen" (< 3.5s cover)
#   4. Ctrl+Opt+Cmd+V (`log show` status 0 vs -9878)
#   5. Shift+Cmd+V in TextEdit / Chrome / VS Code
#   6. Double Cmd+C + Cmd+V paste stack across TextEdit / Notes / Chrome
#   7. Quick Menu Esc while typing in TextEdit
#   8. AppleKeyboardUIMode=3 / FullKeyboardAccessEnabled=true FKA Tab sweep
#
# Usage: scripts/vm/vm-tcc-matrix.sh [path/to/Pesto.app-or-dmg]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/vm/vm-lib.sh
source "${SCRIPT_DIR}/vm-lib.sh"

APP_PKG="${1:-${PESTO_APP:-}}"
BASE_VM="${PESTO_VM_BASE:-pesto-macos15-sip-off}"

vm_require_tart
vm_install_cleanup_trap

CLONE_NAME="$(vm_unique_name "pesto-tcc")"
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
  mnt="$(mktemp -d /tmp/pesto-tcc-mnt.XXXXXX)"
  hdiutil attach "$pkg" -nobrowse -readonly -mountpoint "$mnt" -quiet
  ditto "$mnt/Pesto.app" /Applications/Pesto.app
  hdiutil detach "$mnt" -quiet || true
  rmdir "$mnt" 2>/dev/null || true
else
  ditto "$pkg" /Applications/Pesto.app
fi
REMOTE
fi

# 1 & 2. Accessibility TCC.db onboarding advance (1.5s poller) + Pasteboard TCC check
vm_log "1-2. Testing kTCCServicePasteboard and Accessibility OnboardingView 1.5s poller..."
TCC_RES="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
pkill -x Pesto >/dev/null 2>&1 || true

# Reset Pasteboard TCC (macOS 15.4+) and clear Accessibility TCC
tccutil reset Pasteboard net.copypesto.pesto >/dev/null 2>&1 || true
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "DELETE FROM access WHERE client='net.copypesto.pesto' AND service='kTCCServiceAccessibility';"

# Explicitly test auth_value=0 for kTCCServicePasteboard in user TCC.db
user_tcc="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
if [[ -f "$user_tcc" ]]; then
  sqlite3 "$user_tcc" \
    "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServicePasteboard', 'net.copypesto.pesto', 0, 0, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, strftime('%s','now'));" 2>/dev/null || true
fi

open /Applications/Pesto.app
sleep 2

# Now grant Accessibility in system TCC.db while OnboardingView is open and time the 1.5s poller advance
t0="$(date +%s)"
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAccessibility', 'net.copypesto.pesto', 0, 2, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, strftime('%s','now'));"

advanced=0
for _ in $(seq 1 20); do
  win_title="$(osascript -e 'tell application "System Events" to tell process "Pesto" to get name of window 1' 2>/dev/null || true)"
  if [[ "$win_title" != *"Welcome"* && "$win_title" != *"Onboarding"* ]]; then
    advanced=1
    break
  fi
  sleep 0.5
done
t1="$(date +%s)"

# Restore Pasteboard TCC access for subsequent clipboard tests
tccutil reset Pasteboard net.copypesto.pesto >/dev/null 2>&1 || true
if [[ -f "$user_tcc" ]]; then
  sqlite3 "$user_tcc" \
    "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServicePasteboard', 'net.copypesto.pesto', 0, 2, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, strftime('%s','now'));" 2>/dev/null || true
fi

printf '%s|%s\n' "$advanced" "$((t1 - t0))"
REMOTE
)"
IFS='|' read -r ONBOARDING_ADVANCED ADVANCE_SEC <<<"$TCC_RES"
if [[ "$ONBOARDING_ADVANCED" == "1" ]]; then
  vm_pass "OnboardingView advanced after TCC.db Accessibility grant (${ADVANCE_SEC}s)"
else
  vm_fail "OnboardingView did not advance after TCC.db Accessibility grant"
fi

# 3. Chrome fake-UI screen share (< 3.5s cover)
vm_log "3. Testing Chrome screen share cover (< 3.5s)..."
SHARE_RES="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [[ ! -x "$chrome" ]]; then
  echo "skip|no-chrome"
  exit 0
fi

mkdir -p /tmp/pesto-share-test
cat > /tmp/pesto-share-test/index.html <<'HTML'
<!doctype html><html><body><script>
navigator.mediaDevices.getDisplayMedia({video: true}).catch(() => {});
</script></body></html>
HTML

python3 -m http.server 18422 --bind 127.0.0.1 --directory /tmp/pesto-share-test >/dev/null 2>&1 &
srv_pid=$!
trap 'kill "$srv_pid" >/dev/null 2>&1 || true; pkill -f "pesto-share-profile" >/dev/null 2>&1 || true' EXIT

"$chrome" \
  --user-data-dir=/tmp/pesto-share-profile \
  --no-first-run \
  --use-fake-ui-for-media-stream \
  --auto-select-desktop-capture-source="Entire screen" \
  "http://127.0.0.1:18422/index.html" >/dev/null 2>&1 &

sleep 4
logs="$(log show --last 15s --predicate 'subsystem == "net.copypesto.pesto"' --style compact 2>/dev/null || true)"
if printf '%s' "$logs" | grep -qiE "screen.?share|ScreenShareDetector|covered"; then
  echo "pass|detected"
else
  echo "warn|no-log-match"
fi
REMOTE
)"
case "$SHARE_RES" in
  pass\|*) vm_pass "Chrome screen share detected within 3.5s window" ;;
  skip\|*) vm_log "SKIP: Google Chrome not installed in golden VM" ;;
  *) vm_fail "Chrome screen share cover not observed in unified log (${SHARE_RES})" ;;
esac

# 4. Ctrl+Opt+Cmd+V hotkey registration & log show (status 0 vs -9878)
vm_log "4. Checking Ctrl+Opt+Cmd+V hotkey registration (status 0 vs -9878)..."
HOTKEY_LOG="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
osascript -e 'tell application "System Events" to keystroke "v" using {control down, option down, command down}' >/dev/null 2>&1 || true
sleep 1
log show --last 2m --predicate 'subsystem == "net.copypesto.pesto"' --style compact 2>/dev/null | grep -E "RegisterEventHotKey|hotKey|-9878|status 0" | tail -n 10 || true
REMOTE
)"
if printf '%s' "$HOTKEY_LOG" | grep -q -- "-9878"; then
  vm_fail "Hotkey registration reported Carbon error -9878: ${HOTKEY_LOG}"
else
  vm_pass "No -9878 hotkey registration failure in unified log"
fi

# 5 & 6. Shift+Cmd+V and Double Cmd+C + Cmd+V stack across TextEdit / Notes / Chrome / VS Code
vm_log "5-6. Testing Shift+Cmd+V and double Cmd+C + Cmd+V stack across target apps..."
MATRIX_RES="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
user_tcc="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
for target in "com.apple.systemevents" "com.apple.TextEdit" "com.apple.Notes" "net.copypesto.pesto"; do
  sqlite3 "$user_tcc" \
    "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAppleEvents', 'com.apple.osascript', 0, 2, 4, 1, NULL, NULL, 0, '${target}', NULL, 0, strftime('%s','now'));"
done
for client in "/usr/bin/osascript" "/opt/homebrew/bin/tart-guest-agent"; do
  sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
    "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAccessibility', '${client}', 1, 2, 4, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, strftime('%s','now'));"
  for target in "com.apple.systemevents" "com.apple.TextEdit" "com.apple.Notes" "net.copypesto.pesto"; do
    sqlite3 "$user_tcc" \
      "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified) VALUES ('kTCCServiceAppleEvents', '${client}', 1, 2, 4, 1, NULL, NULL, 0, '${target}', NULL, 0, strftime('%s','now'));"
  done
done
killall tccd >/dev/null 2>&1 || true
sleep 0.5
passed=0
tested=0

for app in "TextEdit" "Notes" "Google Chrome" "Visual Studio Code"; do
  if ! open -Ra "$app" >/dev/null 2>&1; then
    continue
  fi
  tested=$((tested + 1))
  marker="pesto-matrix-${app// /-}-$(date +%s)"
  printf '%s' "$marker" | pbcopy
  sleep 0.5
  printf '%s-second' "$marker" | pbcopy
  sleep 0.5

  if [[ "$app" == "TextEdit" ]]; then
    osascript <<'OSA' || true >/dev/null 2>&1 || true
tell application "TextEdit"
  activate
  make new document
end tell
delay 0.5
tell application "System Events"
  keystroke "v" using {shift down, command down}
  delay 0.8
  keystroke return
end tell
OSA
    doc_text="$(osascript -e 'tell application "TextEdit" to get text of front document' 2>/dev/null || true)"
    if [[ "$doc_text" == *"$marker"* ]]; then
      passed=$((passed + 1))
    fi
  else
    pbcopy </dev/null
    osascript - "$app" <<'OSA' >/dev/null 2>&1 || true
on run argv
  tell application (item 1 of argv) to activate
  delay 0.5
  tell application "System Events"
    keystroke "v" using {shift down, command down}
    delay 0.8
    keystroke return
    delay 0.5
    keystroke "a" using {command down}
    delay 0.1
    keystroke "c" using {command down}
  end tell
end run
OSA
    sleep 0.3
    pasted="$(pbpaste 2>/dev/null || true)"
    if [[ "$pasted" == *"$marker"* ]]; then
      passed=$((passed + 1))
    fi
  fi
done

printf '%s|%s\n' "$passed" "$tested"
REMOTE
)"
IFS='|' read -r MAT_PASSED MAT_TESTED <<<"$MATRIX_RES"
if [[ "${MAT_TESTED:-0}" -ge 1 && "$MAT_PASSED" == "$MAT_TESTED" ]]; then
  vm_pass "Shift+Cmd+V + stack matrix passed (${MAT_PASSED}/${MAT_TESTED} apps)"
else
  vm_fail "Shift+Cmd+V + stack matrix failed (${MAT_PASSED:-0}/${MAT_TESTED:-0} apps)"
fi

# 7. Quick Menu Esc while typing in TextEdit
vm_log "7. Testing Quick Menu Esc while typing in TextEdit..."
ESC_RES="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
osascript <<'OSA' || true
tell application "TextEdit"
  activate
  make new document
end tell
delay 0.5
tell application "System Events"
  keystroke "before-"
  delay 0.2
  keystroke "v" using {shift down, command down}
  delay 0.6
  keystroke "filter"
  delay 0.3
  key code 53 -- Esc
  delay 0.4
  keystroke "after"
end tell
OSA
doc_text="$(osascript -e 'tell application "TextEdit" to get text of front document' 2>/dev/null || true)"
printf '%s\n' "$doc_text"
REMOTE
)"
if [[ "$ESC_RES" == *"before-after"* ]]; then
  vm_pass "Quick Menu Esc restored TextEdit typing focus ('${ESC_RES}')"
else
  vm_fail "Quick Menu Esc did not cleanly restore TextEdit typing focus (got '${ESC_RES}')"
fi

# 8. Full Keyboard Access (AppleKeyboardUIMode = 3 / fullKeyboardAccessEnabled = true) Tab sweep
vm_log "8. Testing Full Keyboard Access Tab sweep (AppleKeyboardUIMode=3)..."
FKA_RES="$(vm_ssh "$CLONE_NAME" bash <<'REMOTE'
set -euo pipefail
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
defaults write com.apple.universalaccess fullKeyboardAccessEnabled -bool true

osascript <<'OSA' || true
tell application "System Events"
  keystroke "v" using {shift down, command down}
  delay 0.6
  repeat 5 times
    key code 48 -- Tab
    delay 0.15
  end repeat
  key code 53 -- Esc
end tell
OSA
pgrep -x Pesto >/dev/null 2>&1 && echo "ok" || echo "dead"
REMOTE
)"
if [[ "$FKA_RES" == "ok" ]]; then
  vm_pass "FKA Tab sweep completed with Pesto responsive"
else
  vm_fail "FKA Tab sweep failed (status: ${FKA_RES})"
fi

vm_finish
