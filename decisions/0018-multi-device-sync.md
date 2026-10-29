# 0018. Macs sync through an encrypted, append-only log per Mac in a folder the person picks; the sync key is a separate key enrolled by hand and never stored with the provider

Status: Proposed

## Context
ADR 0010 gives one backup file per Mac. Restoring one adds what is missing; it is a way back, not a way to keep two Macs
in step. People with two Macs expect a copy on one to appear on the other and a delete on one to delete on both. The
constraints are the ones the backup already meets: the history key is per install and never leaves the Mac (ADR 0002),
there is no server of ours and no new endpoint (ADR 0005), the provider sees only opaque bytes, and secrets stay masked
and opt-in (ADR 0003, 0004). CloudKit-mirrored SwiftData fails these (`docs/sync-design.md`). The provider's folder sync
(iCloud Drive suggested; Dropbox or any synced folder) is the transport. It is eventually consistent, may be slow or
offline, may hand back old file versions and may create conflict copies when two writers touch one file.

## Decision
**Layout: every file has exactly one writer.** In the chosen folder, `Pesto Sync/`:
- `vault.pestosync`: written once by the Mac that creates the sync group (magic, version, vault id of 16 random bytes,
  check value of the sync key). Never rewritten; a rekey writes `vault-<epoch>.pestosync`.
- `devices/<device id>/`: one directory per Mac, named by its random device id, never the Mac's name. Only that Mac
  writes inside it:
  - `device.pestodev`: the device record (name, Ed25519 signing public key, X25519 key-agreement public key, enrolled-by,
    enrolled-at), sealed under the sync key.
  - `log/<first seq>-<last seq>.pestolog`: immutable segments, written as `.partial` and renamed when complete.
  - `blobs/<HMAC(sync key, plain SHA-256)>.pestoblob`: payloads over 256 KB, immutable, referenced by records.
  - `snapshot-<seq>.pestosnap`: periodic compaction of this Mac's own records.
  - `head.pestohead`: the only file a Mac rewrites: its last segment, chain hash, epoch and a cursor for every other Mac
    ("read device X through seq N"). Signed.
- Files that match none of these names (provider conflict copies, foreign files) are ignored and counted in the log.

**Segments reuse the backup framing** (`BackupFile`: header, file id block, AES-GCM-256 chunks bound to
`SHA256(header | file id)`, index and manifest flag) under the sync key of the current epoch. The manifest adds device
id, sequence range, epoch, the SHA-256 of the previous segment's manifest (a hash chain per device) and an Ed25519
signature by the device key. AEAD stops the provider; the signature stops one member forging another's records, which
revocation needs.

**Records** extend the backup's kinds: item (as `BackupItemMetadata`, plain SHA-256 inside the ciphertext), curation
update, collection, tombstone (id **and** plain hash; the backup's are by id only), device enroll, device revoke, rekey.
Every record carries a hybrid logical clock `(wall time, counter, device id)`; the sort triple stays
`(timestamp, sequenceNumber, deviceID)`. A device's next sequence number is `max(counter, own head on disk) + 1`, so a
number is never reused after a crash.

**Merge.** A receiving Mac decrypts with the sync key and applies records through
`StorageService.ingest(_:preferredItemID:rewritesText: false)`, as restore does. Nothing remote is written around ingest,
so masking, the per-install key, item-bound associated data (ADR 0002) and the per-Mac content hash all hold. Each rule is
a pure function in Core:
- Same id: the later clock wins, per record. Title, note, tags, pin, collection and expiry are one curation record, so
  concurrent edits of different fields on two Macs keep the later edit.
- Same content, different ids (both Macs copied it): fold into the id with the earliest clock; curation merges by clock.
- Tombstone: removes the id and any clip with that content whose latest clock is earlier than the tombstone. A later copy
  or an Undo (a new item record with a later clock) brings it back; a replayed old record does not.
- Paste counts merge as a per-device counter (the sum of each Mac's maximum).
- Only the person's own deletes travel (`DeletionReason.user`). Retention sweeps stay per Mac. Clear History offers "Also
  on your other Macs" (off by default). Clear Everything leaves the sync group on this Mac and deletes nothing elsewhere.
- Not synced: link-preview images and search vectors (each Mac makes its own under its own settings), per-Mac state, the
  settings record (a later decision may add it).

**The sync key is separate and enrolled by hand.** A random 256-bit sync key encrypts the folder. The history key of ADR
0002 is untouched and still never leaves the Mac. Each Mac keeps the sync key and its device keys as generic passwords in
the login Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, not synchronizable. Nothing in the folder opens
without a credential the person holds. A further Mac joins one of two ways:
- **Recovery key** (the default; the only way when no other Mac is at hand): the sync key itself, shown once in the
  backup's base32-with-checksum form behind a `ProtectedAction`. The vault holds only a check value of a 256-bit key, so
  the provider has nothing to guess and no slow derivation is needed.
- **Approve from another Mac**: the new Mac writes a join request with its X25519 key into its own directory. An enrolled
  Mac shows the request; both show a six-word code derived from both public keys; on a match the enrolled Mac seals the
  sync key to the new Mac with HPKE (CryptoKit) and signs an enroll record. The code defeats a provider that swaps keys.
- A passphrase is not offered for sync. It would leave an offline-guessable wrapped key with the provider; the backup
  accepts that only because it is one file the person chose to make, and PBKDF2 at 600,000 rounds is the cost there.

**Why not iCloud Keychain** (`kSecAttrSynchronizable`): it needs a keychain access group and a Team ID, which a
self-signed build does not have (the CloudKit blocker again); it puts the folder and the key under one Apple ID recovery;
it works only when the folder is iCloud too, which breaks provider choice; and it contradicts invariant 2 ("not
synchronizable"). It may return as an opt-in convenience after Developer ID, in its own decision.

**Secrets.** A clip with a sensitivity category (masked in the grid, ADR 0003) is not written to the log unless the person
turns on "Sync clips marked sensitive" (off, separate from the backup's choice). A credential (an allowance's concealed
copy, ADR 0004) never syncs. The writer emits a clip only after its judgment finishes (ADR 0006), so a secret is never
logged before it is recognized. A clip marked sensitive after it synced is withdrawn with a tombstone. Clips over 10 MB do
not sync. A synced secret stays masked on the other Mac and Show asks there as usual.

**Rollback, replay, tampering.** Each Mac stores, sealed in its own store, the highest sequence and chain hash it applied
from every other Mac. A head or segment below that, a broken chain, a fork (two segments for one sequence), a bad
signature, a wrong epoch or an unenrolled device is refused, and Settings names the Mac. A provider can withhold files
but cannot forge or roll back undetected; withholding shows as "last heard from <Mac> <time> ago".

**A lost Mac.** From any enrolled Mac, Remove Mac (a `ProtectedAction`) writes a signed revoke record and a rekey: a new
epoch, with the new sync key sealed by HPKE to each remaining Mac's X25519 key, and a new recovery key. Remaining Macs
write new segments under the new epoch and compact the old ones. The removed Mac keeps what it already had (its store is
sealed under its own key) and, sharing the provider account, can still delete files in the folder; Pesto cannot stop that,
and the guide says to also remove the Mac from the Apple ID. The backup remains the way back.

**Latency and a slow provider.** The target comes from measurement, not guesses (phase 0, `docs/perf/sync-latency-*.md`).
Pesto's own share is bounded at 2 s from the judged copy to a renamed segment on A and 2 s from a file's arrival to the
card on B. The end-to-end budget (p50 and p95, A's copy to B's shelf) is the measured iCloud Drive figure plus those 4 s,
asserted by `make bench-sync` on two Macs. Capture, paste and the shelf never wait for sync. When the folder is slow,
offline or unmounted, the outbox is "own records above the last segment written", derived from the store, so nothing
extra is kept. Settings shows the real state (Up to Date, Waiting for the Folder, Offline, Folder Missing, a Mac Not Heard
From, Refused with the reason), never "Connected" by default. A locked history pauses both directions.

**Migration.** New fields are optional (`changeClock`, `syncOrigin`), so the SwiftData migration is lightweight. Joining
never replaces: the first Mac writes a snapshot of its history; a joining Mac shows the counts, then merges both ways
(union by content, tombstones applied). `SyncAvailability.isAvailable` now means "sync works end to end on two Macs" and
flips with the last phase.

**Network.** The provider's own client is the transport. Sync code links no networking API (a scan test enforces it); the
`NetworkGuardTests` allowlist is unchanged.

## Consequences
- The provider learns that Pesto sync exists in the folder, the number of Macs, file sizes and write counts and timing.
  Not names, content or which clip is which (blob names are keyed HMACs).
- The folder grows with history until compaction; a Mac compacts only what every enrolled Mac's cursor has passed.
- Losing every Mac and the recovery key loses the sync group (not the backup, which has its own key).
- Concurrent edits of different curation fields keep only the later edit.
- A revoked Mac cannot read anything new but can vandalize the folder.
- Two secrets now leave a Mac only by the person's hand: the backup key and the sync key.
- Tests: format (flip every byte, truncate, splice segments across devices and epochs), chain and rollback, merge
  convergence (random operations on three simulated Macs, any delivery order, same result), secrets never in a segment
  (scan like `OnDiskEncryptionTests`), migration from a 1.1.0 store, a two-Mac test on a temp folder, `make bench-sync`.

## Docs affected
`AGENTS.md` (security invariant 2 gets a sync-key sentence; a pitfall line for "every sync file has one writer"),
`Sources/Core/Sync/CLAUDE.md`, `Sources/Core/Backup/CLAUDE.md`, `docs/sync-design.md`, `docs/guide/privacy-and-security.md`,
`docs/guide/faq.md`, `docs/guide/moving-from.md`, `docs/guide/settings.md`, `README.md`, `ROADMAP.md`, the website guide
copies and `claim-text.ts`.
