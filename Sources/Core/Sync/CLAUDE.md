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
| `SyncAvailability.swift` | The switch for the whole feature; the person still turns sync on per Mac. |
| `SequenceCounter.swift`, `DeviceIdentity.swift` | Device id (`unknown` refuses to start sync) and the sort tie-breaker. |

## Key invariants

- **Wall-clock timestamps drift across devices.** Sort by `(timestamp, sequenceNumber, deviceID)`, not by `timestamp` alone.

- **Slices crash CryptoKit and HPKE** when `startIndex` is not zero: copy with `Data(...)` before sealing, opening or indexing.
- **A clip is its plain SHA-256 across Macs**, not its id; a deletion is a tombstone by id and hash and only the same id's tombstone is removed by a re-copy.
- **A snapshot is a segment whose manifest says so** (`snapshot`): a reader that is behind applies it despite the gap. Compaction (`SyncFolderService+Compaction.swift`) re-sends only what this Mac last wrote, never what it received.
- **A segment the Mac refuses is not recorded as read**: it is read again once the cause (a key, a clock, a damaged file) is fixed.
