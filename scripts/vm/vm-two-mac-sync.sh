#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Two-Mac iCloud Drive + iCloud Keychain sync verification in two ephemeral
# pre-signed-in macOS 15+ Tart VMs.
#
# Installs a Profile/release build via SSH on both VMs, verifies iCloud Keychain
# auto-join (kSecAttrSynchronizable), then blocks CloudKit/HTTPS on VM B with
# pfctl (preserving SSH port 22) to test offline divergence and convergence.
#
# Usage: scripts/vm/vm-two-mac-sync.sh <path/to/Pesto.app-or-dmg>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/vm/vm-lib.sh
source "${SCRIPT_DIR}/vm-lib.sh"

APP_PKG="${1:-${PESTO_PROFILE_APP:-}}"
BASE_VM_A="${PESTO_SYNC_VM_A:-pesto-macos15-icloud-a}"
BASE_VM_B="${PESTO_SYNC_VM_B:-pesto-macos15-icloud-b}"
SYNC_TIMEOUT="${PESTO_SYNC_TIMEOUT:-120}"

if [[ -z "$APP_PKG" || ! -e "$APP_PKG" ]]; then
  printf 'Usage: %s <path/to/Profile-Pesto.app-or-dmg>\n' "$0" >&2
  exit 2
fi

vm_require_tart
vm_install_cleanup_trap

CLONE_A="$(vm_unique_name "pesto-sync-a")"
CLONE_B="$(vm_unique_name "pesto-sync-b")"

vm_clone "$BASE_VM_A" "$CLONE_A"
vm_clone "$BASE_VM_B" "$CLONE_B"

vm_start "$CLONE_A"
vm_start "$CLONE_B"

install_app_on_vm() {
  local vm="$1"
  local pkg="$2"
  local remote_pkg="/tmp/$(basename "$pkg")"
  vm_copy_to "$vm" "$pkg" "$remote_pkg"
  vm_ssh "$vm" bash -s "$remote_pkg" <<'REMOTE'
set -euo pipefail
pkg="$1"
pkill -x Pesto >/dev/null 2>&1 || true
rm -rf /Applications/Pesto.app
if [[ "$pkg" == *.dmg ]]; then
  mnt="$(mktemp -d /tmp/pesto-sync-mnt.XXXXXX)"
  hdiutil attach "$pkg" -nobrowse -readonly -mountpoint "$mnt" -quiet
  ditto "$mnt/Pesto.app" /Applications/Pesto.app
  hdiutil detach "$mnt" -quiet || true
  rmdir "$mnt" 2>/dev/null || true
else
  ditto "$pkg" /Applications/Pesto.app
fi
REMOTE
}

vm_log "Installing Profile/release build on both VMs via SSH..."
install_app_on_vm "$CLONE_A" "$APP_PKG"
install_app_on_vm "$CLONE_B" "$APP_PKG"
vm_pass "Installed Pesto.app on both VMs"

# Verify iCloud Drive is signed in on both VMs
for vm in "$CLONE_A" "$CLONE_B"; do
  if vm_ssh "$vm" test -d "\$HOME/Library/Mobile Documents/com~apple~CloudDocs"; then
    vm_pass "iCloud Drive directory present on ${vm}"
  else
    vm_die "iCloud Drive not signed in on ${vm}. See scripts/vm/README.md."
  fi
done

# Launch Pesto on VM A and enable sync so it writes the synchronizable sync key
vm_log "Launching Pesto on VM A and enabling sync..."
vm_ssh "$CLONE_A" bash <<'REMOTE'
set -euo pipefail
open /Applications/Pesto.app
for _ in $(seq 1 30); do
  pgrep -x Pesto >/dev/null 2>&1 && break
  sleep 0.5
done
sleep 2
REMOTE

# Check iCloud Keychain auto-join on VM B
vm_log "Launching Pesto on VM B and waiting for iCloud Keychain auto-join..."
vm_ssh "$CLONE_B" bash <<'REMOTE'
set -euo pipefail
open /Applications/Pesto.app
for _ in $(seq 1 30); do
  pgrep -x Pesto >/dev/null 2>&1 && break
  sleep 0.5
done
REMOTE

if vm_wait_for "$SYNC_TIMEOUT" vm_ssh "$CLONE_B" bash -c \
  'security find-generic-password -s "net.copypesto.pesto.sync" >/dev/null 2>&1'; then
  vm_pass "iCloud Keychain sync key auto-joined on VM B"
else
  vm_fail "Timed out waiting for iCloud Keychain sync key on VM B"
fi

# Offline divergence via pfctl (blocks outbound HTTPS/CloudKit on en0, keeps SSH port 22)
vm_log "Isolating VM B network with pfctl (preserving SSH port 22) for offline divergence..."
vm_ssh "$CLONE_B" bash <<'REMOTE'
set -euo pipefail
iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}' || echo "en0")"
sudo tee /tmp/pesto-offline.pf >/dev/null <<PF
pass quick on lo0 all
pass quick on ${iface} proto tcp from any to any port 22
pass quick on ${iface} proto tcp from any port 22 to any
block drop out on ${iface} all
PF
sudo pfctl -e >/dev/null 2>&1 || true
sudo pfctl -a com.apple/pesto-offline -f /tmp/pesto-offline.pf >/dev/null 2>&1 || sudo pfctl -f /tmp/pesto-offline.pf
REMOTE

CLIP_A="sync-diverge-a-$(date +%s)"
CLIP_B="sync-diverge-b-$(date +%s)"

vm_log "Ingesting divergent clips while VM B is offline (${CLIP_A} on A, ${CLIP_B} on B)..."
vm_ssh "$CLONE_A" "printf '%s' '$CLIP_A' | pbcopy"
vm_ssh "$CLONE_B" "printf '%s' '$CLIP_B' | pbcopy"
sleep 3

vm_log "Restoring VM B network (flushing pfctl block) and waiting for convergence..."
vm_ssh "$CLONE_B" bash <<'REMOTE'
set -euo pipefail
sudo pfctl -d >/dev/null 2>&1 || true
sudo ifconfig en0 up >/dev/null 2>&1 || true
REMOTE

check_converged() {
  local vm="$1"
  vm_ssh "$vm" bash <<'REMOTE'
set -euo pipefail
sync_dir="$(find "$HOME/Library/Mobile Documents" -maxdepth 4 -type d -name '*Pesto*' 2>/dev/null | head -n 1 || true)"
if [[ -z "$sync_dir" ]]; then
  exit 1
fi
log_count="$(find "$sync_dir" -type f -name '*.pestolog*' 2>/dev/null | wc -l | tr -d ' ')"
[[ "${log_count:-0}" -ge 2 ]]
REMOTE
}

if vm_wait_for "$SYNC_TIMEOUT" check_converged "$CLONE_A" && vm_wait_for "$SYNC_TIMEOUT" check_converged "$CLONE_B"; then
  vm_pass "Both VMs converged per-Mac sync logs after offline divergence"
else
  vm_fail "Sync logs did not converge on both VMs within ${SYNC_TIMEOUT}s"
fi

vm_finish
