# Multi-device sync: design notes

Sync is **not built**. `SyncAvailability.isAvailable` is `false` (`Sources/Core/Sync/SyncAvailability.swift`), Settings
says so, and CloudKit is never started. What exists is a per-Mac encrypted backup file and restore from any backup file
(see the backup decisions in `decisions/`). These notes record what a sync feature has to solve so that the work can
start from evidence.

## Why CloudKit-mirrored SwiftData does not work today
- The store fails to load with CloudKit on (Core Data error 134060): several non-optional attributes have no default,
  and `@Attribute(.unique)` is on all four models (`ClipboardItem`, `ClipboardBlob`, `DeletedItemTombstone`,
  `Pinboard`). CloudKit forbids uniqueness constraints. Dedupe already uses `contentHash`; `.unique` is only a local
  hint.
- The blob key is per-install and `ThisDeviceOnly`, so a second Mac cannot decrypt synced blobs or previews. Options: a
  key shared through iCloud Keychain, or key wrapping per device.
- Deletions must sync too (tombstones), and `ModelContainerSetup.make(cloudKitEnabled:)` silently falls back to
  local-only, so any UI must show the real tier.
- A CloudKit entitlement needs a Team ID and a provisioning profile; `Pesto.entitlements` is empty for that reason.

## Direction: a provider-agnostic encrypted folder
Safety and privacy come first, and the design must not tie Pesto to one provider (iCloud Drive, Dropbox, a plain
folder). That points away from CloudKit mirroring and toward the encrypted backup format that already exists:
- The provider only ever stores opaque files. Pesto encrypts on the Mac with authenticated encryption, so the provider
  and anyone with its account cannot read history, and a modified file is rejected.
- The key comes from a passphrase (slow salted key derivation) or a recovery key shown once. No key is stored with the
  provider; losing it makes the backup unrecoverable, and the UI says so.
- A versioned format with per-item records and tombstones makes restore deterministic. Merge by `contentHash` and
  tombstones; the sort triple stays in `SequenceCounter` and `DeviceIdentity`.
- Sensitive items are excluded by default, with an explicit opt-in.
- Multi-device then means several Macs reading and writing the same encrypted folder with the same merge rules: no
  server of ours and no endpoint beyond the folder the person picks (`NetworkGuardTests` allowlist unchanged).
- Threats to cover: a stolen backup file, a malicious provider, a replayed old backup (rollback), a compromised device,
  passphrase guessing and restore of tampered data.

## Done when
1. A two-device test shows an item written on Mac A decrypting on Mac B.
2. Deleting on A removes it on B and a re-import does not resurrect it.
3. Settings shows the real state (connected, signed out, restricted, error), never "Connected" by default.
4. `SyncAvailability.isAvailable` flips to `true` with its test.
5. Existing local stores migrate without loss (test on a store made by the current build).
