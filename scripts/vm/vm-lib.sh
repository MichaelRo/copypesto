#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Shared helpers for ephemeral Tart macOS VM test harnesses.
# Source this file from scripts/vm/vm-*.sh; do not execute directly.

set -euo pipefail

VM_USER="${PESTO_VM_USER:-admin}"
VM_SSH_KEY="${PESTO_VM_SSH_KEY:-}"
VM_BOOT_TIMEOUT="${PESTO_VM_BOOT_TIMEOUT:-180}"
VM_TRANSPORT="${PESTO_VM_TRANSPORT:-ssh}"

VM_CLONES=()
VM_FAILURES=0

vm_log() {
  printf '[vm] %s\n' "$*" >&2
}

vm_pass() {
  printf '[PASS] %s\n' "$*"
}

vm_fail() {
  printf '[FAIL] %s\n' "$*" >&2
  VM_FAILURES=$((VM_FAILURES + 1))
}

vm_die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

vm_require_tart() {
  if ! command -v tart >/dev/null 2>&1; then
    cat >&2 <<'EOF'
[ERROR] 'tart' is not installed or not on PATH.

Install Tart on Apple Silicon macOS:
  brew install cirruslabs/cli/tart

See scripts/vm/README.md for golden VM setup (autoLoginUser, /etc/kcpassword,
SSH key auth, and SIP-disabled TCC test image).
EOF
    exit 1
  fi
}

vm_require_base_image() {
  local base="$1"
  if ! tart list --quiet | grep -Fxq "$base"; then
    vm_die "Base Tart VM '$base' not found. Create or pull it first (see scripts/vm/README.md)."
  fi
}

vm_register_clone() {
  local name="$1"
  VM_CLONES+=("$name")
}

vm_cleanup() {
  local clone
  for clone in ${VM_CLONES[@]+"${VM_CLONES[@]}"}; do
    vm_log "Cleaning up ephemeral VM '$clone'..."
    tart stop "$clone" >/dev/null 2>&1 || true
    tart delete "$clone" >/dev/null 2>&1 || true
  done
}

vm_install_cleanup_trap() {
  trap vm_cleanup EXIT INT TERM
}

vm_unique_name() {
  local prefix="$1"
  printf '%s-%s-%s' "$prefix" "$(date +%Y%m%d%H%M%S)" "$$"
}

vm_clone() {
  local base="$1"
  local clone="$2"
  vm_require_base_image "$base"
  vm_log "Cloning '$base' -> '$clone'..."
  tart clone "$base" "$clone"
  vm_register_clone "$clone"
}

vm_ip() {
  local name="$1"
  tart ip "$name" 2>/dev/null || true
}

vm_ssh_opts() {
  local -a opts=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=5
    -o BatchMode=yes
  )
  if [[ -n "$VM_SSH_KEY" ]]; then
    opts+=(-i "$VM_SSH_KEY")
  fi
  printf '%s\n' "${opts[@]}"
}

vm_ssh() {
  local name="$1"
  shift
  if [[ "$VM_TRANSPORT" == "exec" ]]; then
    if [[ ! -t 0 ]]; then
      tart exec -i "$name" "$@"
    else
      tart exec "$name" "$@"
    fi
    return $?
  fi
  local ip
  ip="$(vm_ip "$name")"
  [[ -n "$ip" ]] || vm_die "VM '$name' has no IP address yet"
  local -a opts=()
  while IFS= read -r line; do
    opts+=("$line")
  done < <(vm_ssh_opts)
  ssh "${opts[@]}" "${VM_USER}@${ip}" "$@"
}

vm_copy_to() {
  local name="$1"
  local src="$2"
  local dst="$3"
  if [[ "$VM_TRANSPORT" == "exec" ]]; then
    local src_dir src_base dst_dir
    src_dir="$(cd "$(dirname "$src")" && pwd)"
    src_base="$(basename "$src")"
    if [[ "$dst" == */ ]]; then
      tart exec "$name" mkdir -p "$dst"
      tar -C "$src_dir" -cf - "$src_base" | tart exec -i "$name" tar -xf - -C "$dst"
    else
      dst_dir="$(dirname "$dst")"
      tart exec "$name" mkdir -p "$dst_dir"
      tar -C "$src_dir" -cf - "$src_base" | tart exec -i "$name" bash -c '
        tmp="$(mktemp -d)"
        tar -xf - -C "$tmp"
        rm -rf "$1"
        mv "$tmp/$2" "$1"
        rmdir "$tmp" 2>/dev/null || true
      ' _ "$dst" "$src_base"
    fi
    return $?
  fi
  local ip
  ip="$(vm_ip "$name")"
  [[ -n "$ip" ]] || vm_die "VM '$name' has no IP address yet"
  local -a opts=()
  while IFS= read -r line; do
    opts+=("$line")
  done < <(vm_ssh_opts)
  scp -r "${opts[@]}" "$src" "${VM_USER}@${ip}:${dst}"
}

vm_wait_ready() {
  local name="$1"
  local deadline=$(($(date +%s) + VM_BOOT_TIMEOUT))
  vm_log "Waiting for VM '$name' to boot and accept commands..."
  while [[ "$(date +%s)" -lt "$deadline" ]]; do
    if [[ "$VM_TRANSPORT" == "exec" ]]; then
      if tart exec "$name" /usr/bin/true >/dev/null 2>&1; then
        return 0
      fi
    else
      local ip
      ip="$(vm_ip "$name")"
      if [[ -n "$ip" ]] && vm_ssh "$name" /usr/bin/true >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 2
  done
  vm_die "Timed out after ${VM_BOOT_TIMEOUT}s waiting for VM '$name'"
}

vm_start() {
  local name="$1"
  local mode="${2:---no-graphics}"
  vm_log "Starting VM '$name' ($mode)..."
  tart run "$mode" "$name" >/dev/null 2>&1 &
  vm_wait_ready "$name"
}

vm_stop() {
  local name="$1"
  vm_log "Stopping VM '$name'..."
  tart stop "$name" >/dev/null 2>&1 || true
  sleep 2
}

vm_reboot() {
  local name="$1"
  local mode="${2:---no-graphics}"
  vm_stop "$name"
  vm_start "$name" "$mode"
}

vm_wait_for() {
  local timeout="$1"
  shift
  local deadline=$(($(date +%s) + timeout))
  while [[ "$(date +%s)" -lt "$deadline" ]]; do
    if "$@"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

vm_finish() {
  if [[ "$VM_FAILURES" -gt 0 ]]; then
    vm_die "${VM_FAILURES} check(s) failed"
  fi
  vm_log "All checks passed."
}
