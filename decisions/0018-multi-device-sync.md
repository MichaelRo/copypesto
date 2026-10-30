# 0018. Macs sync through an encrypted, append-only log per Mac in a folder the person picks; the sync key is a separate key that travels in iCloud Keychain once Pesto can use it, and by hand until then

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
update, collection, tombstone (id **and** plain hash; the backup's are by id only), device enroll (interim pairing only), rekey.
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

**The sync key is separate from the history key.** A random 256-bit sync key encrypts the folder. The per-install history
key of ADR 0002 is untouched: it stays this-device-only and not synchronizable, and invariant 2 keeps saying so for it.
Nothing in the folder opens without the sync key.

**Target: the sync key lives in iCloud Keychain.** It is a generic password with `kSecAttrSynchronizable` (account
`sync-key.<vault id>.<epoch>`), so a second Mac signed in to the same Apple ID gets it with no passphrase, recovery key
or pairing screen. This is **blocked until Pesto has a Team ID and a keychain access group** (Developer ID, the same
prerequisite as notarization): a self-signed build cannot use a synchronizable item reliably. If iCloud Keychain is off
or the Mac is signed out, sync shows the real state ("iCloud Keychain Is Off", "Not Signed In to iCloud") and stays off;
it never falls back to a weaker key. **Trust shift, stated plainly:** the sync key's safety then rests on the Apple ID
and on iCloud Keychain's end-to-end encryption, not on a credential only the person holds. Someone who takes over the
Apple ID and its Keychain recovery gets the key, and the same Apple ID usually also holds the iCloud Drive folder. The
history key, the backup key and the backup's passphrase are unaffected.

**Interim, and the choice for any other provider or a person who prefers it: join by hand.** Until the access group
exists, each Mac keeps the sync key as a this-device-only login Keychain item, and a further Mac joins by one of:
- **Recovery key:** the sync key itself, shown once in the backup's base32-with-checksum form behind a
  `ProtectedAction`. The vault holds only a check value of a 256-bit key, so the provider has nothing to guess.
- **Approve from another Mac:** the new Mac writes a join request with its X25519 key into its own directory; an enrolled
  Mac shows it; both show a six-word code derived from both public keys; on a match the enrolled Mac seals the sync key
  to the new Mac with HPKE (CryptoKit) and signs an enroll record. The code defeats a provider that swaps keys.
- A passphrase is not offered: it would leave an offline-guessable wrapped key with the provider.
The two modes share the format; only where the key comes from differs, and the Keychain mode can be added without a
format change.

**Why not iCloud Keychain for the history key:** that would put the data's own key under the Apple ID and break
invariant 2 for every clip, including ones that never sync. Only the sync key, which opens only what the person chose to
put in the folder, takes that trade.

**Off by default, per Mac, and never nudged on.** Sync is a `Setting` (`syncEnabled`, default false) that only the person
turns on, in Settings → Data → Sync; it is per Mac, not carried by the settings backup or export, and it is not switched
on by an update, by onboarding, by joining a folder that holds a vault, or by a banner. Until it is on, Pesto writes no
sync file, creates no sync key and reads no sync folder. Turning it off stops reading and writing at once and leaves the
folder alone; Leave Sync removes this Mac's own directory and its key (the others keep theirs). Setup shows in plain
words what leaves this Mac (encrypted files in the chosen folder), what does not (sensitive clips unless opted in), and
that the provider's account can see sizes and timing.

**The experience (from how other Mac apps do it, below).** Second Mac: sign in, turn Sync on, history arrives in the
background with a visible "Receiving 1,240 of 5,000 clips" progress that never blocks the shelf, newest first. Status is
one line with a real state. No Mac list, no conflicts dialog, no merge prompts. Sensitive clips and clips over 10 MB are
named in a quiet count ("12 clips stay on this Mac"), not hidden. A paste never waits.

**Secrets.** A clip with a sensitivity category (masked in the grid, ADR 0003) is not written to the log unless the person
turns on "Sync clips marked sensitive" (off, separate from the backup's choice). A credential (an allowance's concealed
copy, ADR 0004) never syncs. The writer emits a clip only after its judgment finishes (ADR 0006), so a secret is never
logged before it is recognized. A clip marked sensitive after it synced is withdrawn with a tombstone. Clips over 10 MB do
not sync. A synced secret stays masked on the other Mac and Show asks there as usual.

**Rollback, replay, tampering.** Each Mac stores, sealed in its own store, the highest sequence and chain hash it applied
from every other Mac. A head or segment below that, a broken chain, a fork (two segments for one sequence), a bad
signature or a wrong epoch is refused, and Settings says why without listing Macs. A provider can withhold files
but cannot forge or roll back undetected; withholding shows as "Nothing new from your other Macs since <time>".

**A lost Mac and Reset Sync.** Pesto has no list of Macs and no per-Mac action anywhere in the UI. A lost or stolen Mac
is removed from the Apple ID by Apple (Find My, the Apple ID's device list); in the target mode that stops it receiving
any new sync key. Pesto offers one action, **Reset Sync** (a `ProtectedAction`, Settings → Data → Sync): it generates a
new key and starts a new epoch (`vault-<epoch>.pestosync`, a rekey record, a new recovery key in the interim mode). Every
other Mac picks the new epoch up on its next launch (and when it next notices the new vault file), fetches the new key
(iCloud Keychain, or the recovery key in the interim mode), writes new segments under it and compacts the old ones. A
Mac that has not launched yet keeps working on the old epoch until it does. **What a stolen, still-enrolled Mac keeps:**
everything it already has (its store is sealed under its own key; FileVault and the History
Lock, ADR 0003) and the old sync key, so it can still read the old epoch's files. **What it loses:** every clip copied
after the reset, as long as it does not get the new key, which in the target mode means it is off the Apple ID. Reset Sync
without removing the Mac from the Apple ID does not shut it out, because it would receive the new key too; the guide says
to do both. The thief can also delete files in the shared folder while they share the provider account; the backup
remains the way back.

**Latency and a slow provider.** The target comes from measurement, not guesses (phase 0, `docs/perf/sync-latency-*.md`).
Pesto's own share is bounded at 2 s from the judged copy to a renamed segment on A and 2 s from a file's arrival to the
card on B. The end-to-end budget (p50 and p95, A's copy to B's shelf) is the measured iCloud Drive figure plus those 4 s,
asserted by `make bench-sync` on two Macs. Capture, paste and the shelf never wait for sync. When the folder is slow,
offline or unmounted, the outbox is "own records above the last segment written", derived from the store, so nothing
extra is kept. Settings shows the real state (Up to Date, Waiting for the Folder, Offline, Folder Missing, Nothing New Since a Time, Refused with the reason), never "Connected" by default. A locked history pauses both directions.

**Migration.** New fields are optional (`changeClock`, `syncOrigin`), so the SwiftData migration is lightweight. Joining
never replaces: the first Mac writes a snapshot of its history; a joining Mac shows the counts, then merges both ways
(union by content, tombstones applied). `SyncAvailability.isAvailable` now means "sync works end to end on two Macs" and
flips with the last phase.

**Network.** The provider's own client is the transport. Sync code links no networking API (a scan test enforces it); the
`NetworkGuardTests` allowlist is unchanged.

## Decided while building
Details the first draft left open, settled in the build (phase 1 on).
- **Code layout:** pure value types and the segment format in `Core/Sync` (CryptoKit only, no Storage types, no networking: a scan test enforces it); everything that touches SwiftData in `Core/Storage/Sync`. The segment framing follows the backup's design and shares no code with it, so the directory graph gains no edge.
- **Clock:** a hybrid logical clock `(wall milliseconds, counter, device id)`; receiving a remote stamp makes the local clock later than both, and a stamp more than 7 days ahead of this Mac is refused. The record `sequence` is a separate per-device number, contiguous inside a segment.
- **Crypto:** per-file subkey `HKDF(syncKey, salt: file id, info: "pesto.sync.file.v1")`; chunk associated data is `SHA256(magic|file id)|index|isManifest`; blob names are `HMAC(HKDF(syncKey, "pesto.sync.blobname.v1"), plain SHA-256)`. The manifest names the vault, device, epoch, sequence range, a digest of the chunk tags, the hash of the previous manifest and the signer's key id, and is signed with Ed25519. The head is sealed under a key derived per device and signed; the vault file is signed by its creator and carries `HMAC(syncKey, "pesto.sync.check.v1"|vault id|epoch)`.
- **A clip is its text.** Across Macs a clip is identified by the plain SHA-256 of its payload, not by its id: two Macs that copied the same words are the same clip, so there is no folding of twins and nothing depends on the order records arrive. Each Mac keeps its own ids; a record's id is only a hint. A change of text (a snippet edited, text appended) travels as the same id with a new hash, and a Mac that has that id replaces the old text; a Mac that holds the old text under another id keeps it until its own record or a deletion removes it (rare, accepted).
- **Every change is a whole item record** (metadata, payload inline up to 256 KB, else a named blob file) with a later stamp; the later stamp wins per clip and per collection. A deletion (or a withdrawal) is a tombstone with the stamp and the plain hash; it beats an older record and loses to a later one. Only a clip's own deletion is undone by a later record; a deletion of the same text under another id stays, so an older record cannot bring it back. Verified by seeded property tests: three Macs, random copies, edits, pins and deletions, every record delivered one at a time in any order and twice, ending with the same clips and titles on all.
- **High-water marks** decide each segment: apply, duplicate, gap (wait) or refuse (rollback, fork, broken chain, wrong epoch).
- **Pairing words (interim mode):** six words from a committed 1,024-word list, taken from `SHA256("pesto-pair-v1" | vault id | the two agreement public keys in sorted order)`: sixty bits, the same on both Macs.
- **Recovery key:** the sync key in base32 with a two-byte checksum, groups of four, as the backup's key reads.

## Prior art
Researched 2026-10-29 from vendors' own pages; encryption details of the CloudKit apps are mostly unstated.
- **Paste** syncs history and Pinboards through the person's private iCloud account, off until enabled, per device (a
  work Mac can stay off); first sync on a new Mac downloads in the background and can take minutes; it says sync is not a
  backup. Closest to what Pesto wants; Pesto adds client-side encryption with a key of its own and a provider choice.
- **Raycast Cloud Sync** (Pro, alpha) deliberately excludes clipboard history because it may be sensitive; history stays
  encrypted on the Mac and moving it is a manual database-and-key copy.
- **Alfred** syncs preferences through a person-chosen folder (Dropbox, iCloud) but not the clipboard database, and
  documents provider pitfalls: an unmounted volume at launch is an error, iCloud/Dropbox can cause glitches, and the
  Dropbox Apps folder is unsupported. Lessons: pick any folder, survive an unmounted one, say what is not synced.
- **CloudKit clipboard apps** (Copied, kopyPasta, Clipster, Copier, PasteNow, CloudClip) sync over the private database;
  Copied offers a manual resync that compares local and cloud; a user review of CloudClip reports clips silently
  stopping. Lessons: offer a resync and show real state rather than failing quietly.
- **Maccy** and most open-source managers have no sync.
Pesto's difference to state in the guide: nothing is readable by us or the provider, the sync key never lives in the
history database, and sensitive clips stay home by default.

## Consequences
- The provider learns that Pesto sync exists in the folder, the number of Macs, file sizes and write counts and timing.
  Not names, content or which clip is which (blob names are keyed HMACs).
- The folder grows with history until compaction; a Mac compacts only what every enrolled Mac's cursor has passed.
- In the interim mode, losing every Mac and the recovery key loses the sync group (not the backup, which has its own key).
- Concurrent edits of different curation fields keep only the later edit.
- Until Reset Sync, a lost Mac off the Apple ID can read what was synced under the old key but nothing new after a reset; one still on the Apple ID is not shut out by a reset.
- In the target mode a second Mac needs no user step, and the sync key's safety rests on the Apple ID and iCloud Keychain.
- Reset Sync is the only management action; there is no Mac list to keep correct or to attack.
- The backup key still leaves a Mac only by the person's hand. The sync key does too in the interim mode; in the target mode iCloud Keychain carries it.
- Tests: format (flip every byte, truncate, splice segments across devices and epochs), chain and rollback, merge
  convergence (random operations on three simulated Macs, any delivery order, same result), secrets never in a segment
  (scan like `OnDiskEncryptionTests`), migration from a 1.1.0 store, a two-Mac test on a temp folder, `make bench-sync`.

## Docs affected
`AGENTS.md`: in security invariant 2, after "it is **not** Secure Enclave wrapped)" add "The history key never syncs. A separate sync key (ADR 0018) opens only the sync folder: in iCloud Keychain (`kSecAttrSynchronizable`) once Pesto has a Team ID and keychain access group, until then a this-device-only item joined by recovery key or pairing"; and a pitfall line "every sync file has one writer; no UI lists or manages Macs, Reset Sync is the only action",
`Sources/Core/Sync/CLAUDE.md`, `Sources/Core/Backup/CLAUDE.md`, `docs/sync-design.md`, `docs/guide/privacy-and-security.md`,
`docs/guide/faq.md`, `docs/guide/moving-from.md`, `docs/guide/settings.md`, `README.md`, `ROADMAP.md`, the website guide
copies and `claim-text.ts`.
