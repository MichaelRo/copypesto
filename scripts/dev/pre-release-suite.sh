#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Interactive & automated runner for the pre-release verification checklist (docs/testing.md).
#
# Usage:
#   scripts/dev/pre-release-suite.sh [--auto-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUTO_ONLY=0
if [ "${1:-}" = "--auto-only" ]; then
  AUTO_ONLY=1
fi

echo "======================================================================"
echo "  Pesto Pre-Release Verification Suite (docs/testing.md)"
echo "======================================================================"
echo ""

# --------------------------------------------------------------------
# 1. Automated Diagnostic Checks
# --------------------------------------------------------------------
echo "=== Phase 1: Automated Checks ==="
echo ""

# 1.1 Process & Environment
echo "[1/7] Process & Memory Budget:"
PESTO_PID=$(pgrep -x Pesto | head -1 || true)
if [ -n "$PESTO_PID" ]; then
  PESTO_PATH=$(ps -p "$PESTO_PID" -o comm=)
  echo "  ✓ Pesto is running (PID: $PESTO_PID) from: $PESTO_PATH"
  
  # Footprint
  FOOTPRINT_KB=$(footprint "$PESTO_PID" 2>/dev/null | grep -E "Footprint:" | head -1 || true)
  if [ -n "$FOOTPRINT_KB" ]; then
    echo "  ✓ $FOOTPRINT_KB (Budget: < 150 MB steady state)"
  fi

  # Malloc flags
  MALLOC_FLAGS=$(ps eww "$PESTO_PID" | tr ' ' '\n' | grep Malloc || true)
  if echo "$MALLOC_FLAGS" | grep -q "MallocNanoZone=0" && echo "$MALLOC_FLAGS" | grep -q "MallocLargeCache=0"; then
    echo "  ✓ Memory allocators correctly configured (MallocNanoZone=0, MallocLargeCache=0)"
  else
    echo "  ⚠ Memory allocator flags missing or partial: $MALLOC_FLAGS"
  fi
else
  echo "  ✗ Pesto is NOT currently running. Launch with 'make run' or open ~/Applications/Pesto.app"
fi
echo ""

# 1.2 Crash / Exception Logs
echo "[2/7] Crash & Exception Logs:"
EXCEPTION_FILE="$HOME/Library/Application Support/net.copypesto.pesto/last-exception.txt"
if [ -f "$EXCEPTION_FILE" ]; then
  echo "  ⚠ Found SwiftData exception log ($EXCEPTION_FILE):"
  sed 's/^/    /' "$EXCEPTION_FILE"
else
  echo "  ✓ No SwiftData crash log found ($EXCEPTION_FILE clean)"
fi
echo ""

# 1.3 Keychain & Encryption
echo "[3/7] Keychain & Encryption Key:"
if security find-generic-password -s net.copypesto.pesto -a net.copypesto.pesto.blobKey >/dev/null 2>&1; then
  echo "  ✓ Keychain item 'net.copypesto.pesto.blobKey' exists and is accessible."
else
  echo "  ✗ Keychain item 'net.copypesto.pesto.blobKey' not found!"
fi
echo ""

# 1.4 Storage & Metadata Files
echo "[4/7] Local Storage & Permissions:"
SUPPORT_DIR="$HOME/Library/Application Support/net.copypesto.pesto"
if [ -f "$SUPPORT_DIR/clips.store" ]; then
  STORE_SIZE=$(du -h "$SUPPORT_DIR/clips.store" | cut -f1)
  echo "  ✓ Primary store exists: $SUPPORT_DIR/clips.store ($STORE_SIZE)"
else
  echo "  ✗ Store not found at $SUPPORT_DIR/clips.store"
fi

if [ -f "$SUPPORT_DIR/last-item.json" ]; then
  PERMS=$(stat -f "%OLp" "$SUPPORT_DIR/last-item.json" 2>/dev/null || stat -c "%a" "$SUPPORT_DIR/last-item.json" 2>/dev/null || echo "unknown")
  if [ "$PERMS" = "600" ]; then
    echo "  ✓ last-item.json exists with secure owner-only permissions (600)"
  else
    echo "  ⚠ last-item.json permissions are $PERMS (expected 600)"
  fi
fi
echo ""

# 1.5 Installed Competitor Apps (for Multi-Manager Import Offer)
echo "[5/7] Multi-Manager Import Detection:"
for bid in "com.wiheads.paste" "com.wiheads.paste-setapp" "org.p0deje.Maccy" "com.runningwithcrayons.Alfred"; do
  APP_PATH=$(mdfind "kMDItemCFBundleIdentifier == '$bid'" 2>/dev/null | head -1 || true)
  if [ -n "$APP_PATH" ]; then
    echo "  ✓ Found: $bid -> $APP_PATH"
  else
    echo "  - $bid: not installed"
  fi
done
echo ""

# 1.6 Hotkey Registrations
echo "[6/7] Hotkey Registration Status:"
HOTKEY_LOGS=$(/usr/bin/log show --last 15m --predicate 'subsystem == "net.copypesto.pesto" AND category == "hotkey"' --style compact 2>/dev/null | grep -E "Registered|Pressed" | tail -n 5 || true)
if [ -n "$HOTKEY_LOGS" ]; then
  echo "$HOTKEY_LOGS" | sed 's/^/  /'
else
  echo "  ℹ No hotkey registration events in last 15m."
fi
echo ""

# 1.7 URL Scheme Handler
echo "[7/7] Testing URL Scheme (pesto://open)..."
if open -g "pesto://open" 2>/dev/null; then
  echo "  ✓ Successfully invoked 'open -g pesto://open'"
else
  echo "  ⚠ Failed to invoke 'pesto://open'"
fi
echo ""

echo "✓ Automated Phase 1 checks complete."
echo ""

if [ "$AUTO_ONLY" -eq 1 ]; then
  exit 0
fi

# --------------------------------------------------------------------
# 2. Interactive Manual Checklist Walkthrough
# --------------------------------------------------------------------
echo "======================================================================"
echo "=== Phase 2: Interactive Manual Checklist Walkthrough ==="
echo "======================================================================"
echo "Instructions: Press [Enter] to pass an item, [f] to mark failed, or [s] to skip."
echo ""

declare -a CHECKLIST=(
  "1.1 Fresh Install / Onboarding: Onboarding screen appears with prompt when state is reset"
  "1.2 Clipboard Access Warning: System Settings -> Privacy -> Paste from Other Apps (Deny/Ask warning in Pesto)"
  "1.3 Sparkle Updates: 'Check for Updates…' shows dev build toast 'This build does not check for updates.'"
  "2.1 Copy from shelf: Card menu -> Copy moves clip to front without changing paste count"
  "2.2 Copy (⌘C) on shelf: Copies focused clip silently; copies text in search field"
  "2.3 Quick Look (⌘Y): Animating GIF, PDF page, WebP, files with arrow keys"
  "2.4 AI result Paste: Run action on text clip, Return pastes into prior app (Apple Intelligence)"
  "2.5 ⌘⇧V from apps: Shelf & quick menu open in TextEdit, VS Code, Chrome, Slack; paste lands"
  "2.6 Paste all kinds: Text, link, picture, file into apps via Return and double-click"
  "2.7 Shortcut recorder: Refuses duplicate ⌘⇧V, refuses pinned ⌃1, cancels on Esc"
  "2.8 Plain text paste (⌃⌥⌘V): Pastes unformatted plain text"
  "2.9 Double ⌘C & Stacks: Double ⌘C in real app, ⌘V stack pastes in sequence"
  "2.10 Drag & Drop: Drag cards into TextEdit, Notes, Safari address bar"
  "2.11 Shelf at Top (under notch): Settings -> Appearance -> Top hangs below notch, hover card opens below"
  "3.1 Touch ID Lock & Unlock: Shelf locks, Touch ID / password prompt unlocks"
  "3.2 Concealed copies: Password managers (1Password / Apple Passwords) copies are ignored"
  "3.3 Secret Revelation: Masked secret reveals on Show, hides on shelf close / lock / cover"
  "3.4 Screen Share Privacy: Google Meet screen share in Chrome blurs/covers shelf within 3s"
  "3.5 Hide Clip Contents: Trigger from menu bar icon, cards blur immediately"
  "4.1 Theme Switching: All themes (Basil, Mortar, Parmesan, Pine Nut) look correct in light and dark"
  "4.2 Menu Bar Icon: Icon visible and clear in both light and dark menu bar modes"
  "4.3 Card Typography & Whitespace: Option B hierarchy, first-word start, dotted paragraph gap"
  "4.4 Hover Card: Dwell over card opens hover panel without flicker, closes on pointer leave"
  "4.5 Snippet Editor: In Settings -> Snippets, add/edit/delete snippets with ⌃N keycaps"
  "6.1 Delete & Undo: Delete clip(s) -> Undo banner appears -> ⌘Z restores clip in-place"
  "6.2 Delete Warning: Shows 'You can undo with ⌘Z' for normal clips vs 'This can't be undone' for secrets"
  "6.3 Silent Keys: ⌘S on non-image, ⌘0, ⌃-letter swallow beeps without system error sound"
  "6.4 Recent Review Polish: AI panel height adapts, Undo banner doesn't cover card headers"
)

PASSED=0
FAILED=0
SKIPPED=0

for item in "${CHECKLIST[@]}"; do
  echo "------------------------------------------------------------------"
  echo "👉 $item"
  read -r -p "   Result [Enter=PASS / f=FAIL / s=SKIP]: " res
  case "$res" in
    f|F)
      echo "   ✗ FAILED"
      FAILED=$((FAILED + 1))
      ;;
    s|S)
      echo "   - SKIPPED"
      SKIPPED=$((SKIPPED + 1))
      ;;
    *)
      echo "   ✓ PASSED"
      PASSED=$((PASSED + 1))
      ;;
  esac
done

echo ""
echo "======================================================================"
echo "  Walkthrough Summary"
echo "  Passed: $PASSED  |  Failed: $FAILED  |  Skipped: $SKIPPED"
echo "======================================================================"
