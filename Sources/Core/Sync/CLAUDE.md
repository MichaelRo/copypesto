# Core/Sync — notes

The sync file format and keys (ADR 0018), pure CryptoKit and value types: stamps, records, segments, vault, head, manifest, pairing,
key stores. No SwiftData, no Storage types, no networking (`SyncNetworkScanTests`; `Sync` may import only `Crypto`, ADR 0005). Everything that
touches the store lives in `Core/Storage/Sync/` (journal, outbox, `applySync`, `SyncFolderService`, `SyncController`). The user-facing side is
`Features/Settings/Sync*.swift`. Design and decisions: `decisions/0018-multi-device-sync.md`, `docs/sync-design.md`.

## High-risk zones

| Path | Blast radius |
|---|---|
| `SyncSegment.swift`, `SyncManifest.swift`, `SyncHighWater.swift` | The wire format; a change needs a version bump and a reader for the old one. Every byte is tested (flip, truncate, splice). |
| `SyncKey*.swift`, `SyncThisDeviceKeys.swift`, `SyncKeychain.swift` | Where the sync key lives; a change can strand a Mac outside its group. |
| `SyncStamp.swift` | The clock that decides every conflict; a stamp more than 7 days ahead is refused, never trusted. |
| `SequenceCounter.swift`, `DeviceIdentity.swift` | Device id (`unknown` refuses to start sync) and the sort tie-breaker. |

## Key invariants

- **Wall-clock timestamps drift across devices.** Sort by `(timestamp, sequenceNumber, deviceID)`, not by `timestamp` alone.

- **Slices crash CryptoKit and HPKE** when `startIndex` is not zero: copy with `Data(...)` before sealing, opening or indexing.
- **A record is matched by id first, then by its plain SHA-256** (ADR 0053): a clip held here under the record's id is that clip whatever its text; a record whose id is unknown here is the clip with the same text. A deletion is a tombstone by id and hash (by id alone while another clip still holds the text), and only the same id's tombstone is removed by a re-copy.
- **A snapshot is a segment whose manifest says so** (`snapshot`): a reader that is behind applies it despite the gap. Compaction (`SyncFolderService+Compaction.swift`) re-sends only what this Mac last wrote, never what it received.
- **A segment the Mac refuses is not recorded as read**: it is read again once the cause (a key, a clock, a damaged file) is fixed.
- **A clip with no stamp never leaves.** The journal stamps only while sync is on, so the history from before needs a stamp: a joining or new-epoch device restamps everything (`.notFrom`), the device that makes the group restamps at `turnOn`, and an announced device stamps whatever is still unstamped once per run (`.unstamped`), which repairs a first device that made its group before `turnOn` did.
- **A small file in the folder (vault, device record, identity, grant, join request) is read through `SyncSmallFile`, never `Data(contentsOf:)`** (ADR 0038, `SyncSmallFileScanTests`): the folder is untrusted and a planted multi-gigabyte file would be loaded whole. A tombstone carries no hash of a clip that holds a secret.
- **Where the folder comes from is a `SyncFolderSource`** (`Core/Storage/Sync`): the Mac passes a path, the iOS app a
  `BookmarkedSyncFolder` (the picked folder as a security-scoped bookmark in `Setting.syncFolderBookmark`, held open
  from `resolve` or `choose` to `relinquish`, in balance). `SyncController` only ever sees the URL. A stale bookmark
  that still opens the folder is made again and stored (Apple's pattern); one that does not, or an unresolvable one,
  is a repair ("Choose the folder again"), never a state that reads as working. The iOS `SyncFolderWatcher` has no
  `deinit { stop() }`: `NSFileCoordinator` retains a presenter until it is removed, so `stop()` is the only way out.
- **An iPhone's folder is held per holder** (`MobileSync.Holder`: the app in front, a background refresh) and let go
  when the last one is done; `SyncFolderService.stop()` cancels the pass in flight, and `applySync` checks for
  cancellation between records, so a pass never runs on after the security scope ended.
- **Sync wording takes a `SyncDeviceKind`**: a Mac reads the sentences it always had (`SyncCopyTests` pins them); an
  iPhone or iPad names itself and calls the others devices. A new sync sentence takes the kind too.
- **A Mac keeps the group and epoch it joined** (`SyncHighWater.vaultFloor`, ADR 0039): `open(preferring:)` ignores a vault planted beside the real one, and an older epoch or another group is refused. Leave Sync and a folder change clear the floor (they reset the high-water state); Reset Sync resets only the marks (`resetMarks`), never the floor. The pairing words are eight and stretched; change the derivation and the fixed vector in `SyncFormatTests` fails on purpose.
