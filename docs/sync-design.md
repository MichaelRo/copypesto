# Multi-device sync: design notes

Sync is **built** (ADR 0018, Accepted): the feature is off on every Mac until its person turns it
on in Settings → Data, and CloudKit is never started. These notes keep the reasons and the plan; the decisions are in the ADR.
Compaction and snapshots are built. Still open: `make bench-sync`, the measured iCloud latency, the provisioning profile for the iCloud Keychain key
(`docs/release.md`), and the two-Mac check (`docs/testing.md`, "Two Macs: sync").

## Why CloudKit-mirrored SwiftData does not work today
- The store fails to load with CloudKit on (Core Data error 134060): several non-optional attributes have no default,
  and `@Attribute(.unique)` is on all four models (`ClipboardItem`, `ClipboardBlob`, `DeletedItemTombstone`,
  `Pinboard`). CloudKit forbids uniqueness constraints. Dedupe already uses `contentHash`; `.unique` is only a local
  hint.
- The blob key is per-install and `ThisDeviceOnly`, so a second Mac cannot decrypt synced blobs or previews. Options: a
  key shared through iCloud Keychain, or key wrapping per device.
- Deletions must sync too (tombstones), and a CloudKit-backed `ModelContainerSetup` (removed) silently fell back to
  local-only, so any UI must show the real tier.
- A CloudKit entitlement needs a Team ID and a provisioning profile; `Pesto.entitlements` is empty for that reason.

## Direction
Decided in [ADR 0018](../decisions/0018-multi-device-sync.md) (proposed): one encrypted, append-only log per Mac in a
folder the person picks, merged by content hash, clocks and tombstones; a separate sync key (in iCloud Keychain once Pesto has a
Team ID and keychain access group, joined by recovery key or approval from another Mac until then); Reset Sync as the only
management action, no list of Macs; no server of ours and an unchanged `NetworkGuardTests` allowlist.

Sync is off by default, per Mac, and never nudged on (ADR 0018). Prior art for the experience is in the ADR.

## Phased plan
One PR per phase, tests green in each, the full gate once before merging the last.
0. **Measure iCloud Drive** (`scripts/sync-latency/`, not shipped; needs two Macs): A writes a small and a 5 MB file every
   30 s for an hour, B records arrival by FSEvents and a 5 s poll, clocks corrected with `sntp`. Conditions: awake on
   Wi-Fi, B after sleep, Low Power Mode, Optimize Mac Storage (dataless files). Also check that FSEvents fires on a
   download into `com~apple~CloudDocs`, that `startDownloadingUbiquitousItem` works outside an app container, and what
   `pread` does on a dataless file. Output `docs/perf/sync-latency-2026-11.md` with p50 and p95; it sets the budget.
1. **Format** (`Core/Sync`): `SyncSegment` on the `BackupFile` framing, records, hash chain, Ed25519 signatures, high-water
   marks. Make `SequenceCounter` use `AppDefaults.store` and never reuse a number; refuse to start on device id `unknown`.
2. **Change journal** (`Core/Storage`): hybrid logical clock, `changeClock` on items and collections set only in
   `StorageService`, `ClipEditor` and `CollectionStore`; emit after judgment; secrets and credentials filtered; migration
   test on a 1.1.0 store.
3. **Merge engine**: pure merge functions and `StorageService.applySync(_:)` through ingest; convergence property tests.
4. **Keys**: sync key, vault file, interim recovery-key create and join, this-device Keychain items, epochs and Reset Sync.
   The `kSecAttrSynchronizable` mode is added when Developer ID and the access group exist (no format change).
5. **Transport** (`SyncFolderService` actor): writer with a 2 s batch window, FSEvents reader with a poll fallback,
   compaction, status states; starts only when `LaunchMode.current.usesSystemIntegrations`; tests use a temp folder.
6. **UI and pairing**: Settings → Data → Sync (set up, join, sensitive opt-in, Reset Sync, real
   state), `SettingsIndex` entries, `Setting.syncEnabled` (default false, added to `Setting.allNames`, not in the export), first-sync progress that never blocks the shelf, approval with the six-word code. No Mac list; Reset Sync is the one action. UI and snapshot tests first.
7. **Ship**: two-Mac check, `make bench-sync` within budget, ADR to
   Accepted, README, guide and website.

## Done when
1. A two-device test shows an item written on Mac A decrypting on Mac B.
2. Deleting on A removes it on B and a re-import does not resurrect it.
3. Settings shows the real state, never "Connected" by default.
4. Sync is off until a person turns it on, on each Mac (`Setting.syncEnabled`).
5. Existing local stores migrate without loss (test on a store made by the current build).
