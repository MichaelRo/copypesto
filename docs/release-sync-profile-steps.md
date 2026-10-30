# Sync key in iCloud Keychain: Apple portal steps (Michael)

Needed only for the invisible iCloud Keychain key. Without it, sync works with the recovery key or the six-word approval.

## 1. Create the App ID (once)
1. Open https://developer.apple.com/account → **Certificates, Identifiers & Profiles** → **Identifiers** → the blue **+**.
2. Choose **App IDs** → Continue → **App** → Continue.
3. Description: `Pesto`. Bundle ID: select **Explicit** and enter `net.copypesto.pesto`.
4. Leave Capabilities as they are. Keychain Sharing is not a portal capability (it is an Xcode entitlement); an explicit App ID already authorizes the keychain access group `<Team ID>.net.copypesto.pesto`.
5. Continue → **Register**.

## 2. Create the Developer ID profile
1. **Profiles** → **+** → under *Distribution* choose **Developer ID** (macOS) → Continue.
2. Pick the App ID `net.copypesto.pesto`, then your *Developer ID Application* certificate.
3. Name it `Pesto Sync`, generate it, download it, and double-click the file to install it.

## 3. Check the signing (no release, no notarization)
Tell Claude the profile is installed. It runs a signing-only archive and export with `SYNC_PROFILE="Pesto Sync"` and then:

    scripts/check-sync-signing.sh <path to the exported Pesto.app>

Launch the app once: "No matching profile found" in the log means the profile does not match the App ID.

The proof that the key travels through iCloud Keychain is the two-Mac check in `docs/testing.md` ("Two Macs: sync").
