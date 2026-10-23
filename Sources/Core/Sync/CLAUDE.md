# Core/Sync — notes

Device identity and the sort tie-breaker for a future multi-device sync. Sync itself is off (`SyncAvailability`); see
`docs/sync-design.md`. SwiftData model constraints live in `Core/Storage`.

## High-risk zones

| Path | Blast radius |
|---|---|
| `SyncAvailability.swift` | Off in v1. Do not start CloudKit or show "Connected". |
| `SequenceCounter.swift` | Monotonic per-device counter feeding the sort tie-breaker; a reset reorders everyone's history. |
| `DeviceIdentity.swift` | Stable per-device ID used in the sort triple and conflict resolution. |

## Key invariants

- **Wall-clock timestamps drift across devices.** Sort by `(timestamp, sequenceNumber, deviceID)`, not by `timestamp` alone.
