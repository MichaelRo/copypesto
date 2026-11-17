# Ephemeral Tart macOS VM Harnesses

Automated verification harnesses for Pesto behaviors that require a real macOS login session, Gatekeeper quarantine, Sparkle replacement, TCC/Accessibility permissions, or two-Mac iCloud sync. Every script clones an ephemeral VM from a golden base image and deletes the clone on `EXIT`.

## 1. Install Tart

```bash
brew install cirruslabs/cli/tart
```

## 2. Golden VM Setup (`pesto-macos15-golden`)

1. Pull or create a macOS 15+ VM (e.g. `tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest pesto-macos15-golden`).
2. Boot with graphics (`tart run pesto-macos15-golden`), complete Setup Assistant, enable **System Settings → General → Sharing → Remote Login (SSH)**, and add your host SSH public key to `~/.ssh/authorized_keys`.
3. Enable **auto-login** (`autoLoginUser` + `/etc/kcpassword`) so `vm-login-reboot.sh` and GUI tests land directly on an unlocked desktop after reboot:

   ```bash
   # Inside the VM (replace <user> and <password>):
   sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string "<user>"
   # Generate /etc/kcpassword (macOS XOR-obfuscated password) or enable Automatic Login in
   # System Settings -> Users & Groups -> Automatically log in as <user>.
   sudo chmod 600 /etc/kcpassword
   ```

4. Grant passwordless `sudo` for the test user (`echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/tart-test`).
5. Shut down cleanly (`sudo shutdown -h now`).

### Optional Specialized Base Images

- **`pesto-macos15-sip-off`** (required by `vm-sparkle-update.sh` and `vm-tcc-matrix.sh`): Clone `pesto-macos15-golden`, boot into macOS Recovery (`tart run --recovery pesto-macos15-sip-off`), run `csrutil disable` in Terminal, and reboot. This allows direct `sqlite3` writes to `/Library/Application Support/com.apple.TCC/TCC.db`.
- **`pesto-macos15-icloud-a` & `pesto-macos15-icloud-b`** (required by `vm-two-mac-sync.sh`): Two clones signed into the same Apple Account with **iCloud Drive** and **iCloud Keychain** enabled.

## 3. Harnesses

| Script | Purpose | Default Base VM |
|---|---|---|
| `vm-lib.sh` | Shared Tart clone/run/SSH/cleanup helpers | — |
| `vm-gatekeeper-dmg.sh <dmg>` | Quarantine stamp, `syspolicy_check --json`, `CoreServicesUIAgent` `"Open"` → Onboarding | `pesto-macos15-golden` |
| `vm-sparkle-update.sh <prev> <archive> <appcast>` | Loopback `SUFeedURL`, Sparkle 2 CLI update, zero `SecurityAgent`, preserved history & AX | `pesto-macos15-sip-off` |
| `vm-login-reboot.sh [app-or-dmg]` | `sfltool dumpbtm`, Launch at login ON/OFF across `tart stop` + `tart run` | `pesto-macos15-golden` |
| `vm-keychain-loss.sh [app-or-dmg]` | Delete `blobKey`, assert unlock alert & exit `44` until `"Start With Empty History"` | `pesto-macos15-golden` |
| `vm-tcc-matrix.sh [app-or-dmg]` | `kTCCServicePasteboard`, `OnboardingView` 1.5 s poller, Chrome screen share, `⌃⌥⌘V`, `⇧⌘V`, stack, `Esc`, FKA | `pesto-macos15-sip-off` |
| `vm-two-mac-sync.sh <profile-app-or-dmg>` | Two-Mac iCloud Keychain auto-join + `pfctl` offline divergence/convergence | `pesto-macos15-icloud-{a,b}` |

## 4. Environment Overrides

- `PESTO_VM_BASE` — override the default base VM name.
- `PESTO_VM_USER` — SSH username inside the VM (default: `admin`).
- `PESTO_VM_SSH_KEY` — path to SSH private key if not using default agent/keys.
- `PESTO_VM_TRANSPORT` — `ssh` (default) or `exec` (`tart exec`).
- `PESTO_VM_BOOT_TIMEOUT` — seconds to wait for VM boot/SSH (default: `180`).
