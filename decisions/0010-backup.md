# 0010. The backup is one encrypted, chunk-authenticated file per Mac, kept current automatically and guarded against shrinking; sync is designed, not built

Status: Accepted

## Context
History is sensitive and its on-disk key is per install and this-device-only (ADR 0002), so it cannot leave the Mac by
design. People still need a way back after a lost or replaced Mac, on any provider (iCloud Drive, Google Drive, Dropbox,
a plain folder), with no server of ours, no new network endpoint (ADR 0005) and a provider that sees only opaque bytes.
A restore must survive a tampered, truncated or mixed-up file, must not hold a multi-gigabyte history in memory and must
not resurrect clips the person deleted on purpose. A good backup must also never be replaced by a bad one.

## Decision
**Keys.** A random 256-bit backup key (`BackupKey`) encrypts everything. The file wraps it under a key derived from a
passphrase with PBKDF2-HMAC-SHA256 (600,000 iterations, random 16-byte salt, CommonCrypto; `BackupKeyDerivation`); the
KDF id and cost are in the header, so another KDF is a new id within version 1. The alternative credential is a
printable recovery key (the backup key plus a 2-byte checksum, base32 in groups of four; the checksum catches a typo).
An empty passphrase is not allowed. A recovery-key-only backup wraps the header under a random value that is thrown
away, so only the recovery key opens it; the restore sheet accepts either credential. The backup key lives in the login
Keychain. Show Recovery Key sits behind a `ProtectedAction` (ADR 0003); copying it uses the concealed marker. Losing the
Keychain key and the recovery key loses the backup, and setup asks for confirmation that the key was stored.

**Format (version 1, `BackupFile`).** Header (`PSTOBKUP`, version, KDF id and iterations, salt, wrap nonce, wrapped key,
key check), a file-id block (`PSTOFILE` plus 16 random bytes), then chunks: length, nonce, AES-GCM-256 ciphertext, tag.
A chunk's associated data is `SHA256(header | file id)`, its index and an is-manifest flag, so a changed header, or a
chunk reordered, dropped, duplicated, spliced or taken from another file fails authentication. The file id matters
because an automatic backup reuses its header (the passphrase is never kept). A file without the block still opens: its
marker reads as a chunk length over a gigabyte, which no real chunk has. The last chunk is a manifest (record count, a
sequence that rises with every backup a device writes, device id, creation time).

**Records** are item, collection, tombstone and settings (kind 4, whole JSON, never parsed by Core). Clips carry their
curation (title, note, tags, pin, collection, shortcut, expiry). A payload is decrypted with this Mac's key and
re-sealed under the backup key; a record carries a plain SHA-256 because the stored content hash is keyed per Mac. Clips
holding secrets are left out unless the person opted in; clips over 10 MB (`AutoBackupSettings.largestClipBytes`) are
always left out and counted. Dates are exact numbers.

**Deletions.** A tombstone means "deleted on purpose". Only the person's own delete writes one (`DeletionReason.user`:
menu, Delete key, burn after paste). Retention sweeps, Clear Everything, restore, unreadable-clip cleanup and a
double-copy fold do not. Tombstones expire after a year (`StorageService.tombstoneLifetime`).

**Restore is two passes over one open file.** `BackupFile.verify(url:credential:)` authenticates the header, every chunk
and the manifest count, keeping only collections and tombstones; the sheet's counts, date and an "older than the last
backup made on this Mac" warning come from `VerifiedBackup`. Then `StorageService.restore(_:)` applies deletions, then
collections, then hands each clip to `ingest(_:preferredItemID:)`, re-authenticating each chunk. Ingest, never direct
model writes, keeps masking and encryption; a clip present by id or content is skipped, so restoring twice changes
nothing. The file is read with `pread` on a descriptor `VerifiedBackup` keeps open (`FileHandle` pages stayed resident:
78 to 84 MB against 2 to 6 MB for 80 MB), so a replaced or deleted file does not change this restore.

**One backup per Mac.** `AutoBackupService` is the only writer; `BackupCoordinator` only restores. Set Up Backup asks
for the folder, the protection and whether secrets are included, with a switch (on by default,
`AutoBackupSettings.runsAutomatically`) for keeping it current; off, only Back Up Now writes. Restore from Backup takes
any backup file. iCloud Drive (`Pesto` folder) is the default when present. The file is named with the Mac's name and
the first 8 characters of its device id, so Macs sharing a folder never collide. A run happens 5 minutes after the last
change and at most once an hour (`AutoBackupPolicy`), writes `<file>.partial`, and replaces the target only after the
manifest and the guard pass; the old file is kept as `<name>.previous.pestobackup`. Setup refuses if the folder holds a
backup and this Mac has no backup key.

**The guard** (`AutoBackupGuard`) refuses to replace a backup when the store is only in memory, the file in the folder
is under another key, any clip's blob will not decrypt, the person kept the backup after Clear Everything, or the clip
count is under half the baseline (histories under 10 clips, `smallestHistoryJudged`, are not judged). The baseline
(`lastClipCount`) only rises; it falls when the person confirms Replace Backup or by exactly the clips removed on
purpose (retention, a confirmed Clear History range; `AutoBackupSettings.lowerBaseline(by:)`). Clear Everything resets
it and asks whether to keep or delete the backup. Unreadable clips are listed in `BackupExportSummary.unreadableIDs`
(ids go to the log) and Delete Unreadable Clips removes them without a tombstone.

**The backup carries the settings** (the kind 4 record, from `SettingsBackupManager`). Never in it: the History Lock,
the screen-sharing blur, the exclusion list, link previews, per-Mac state (window frame, onboarding) and the backup's
own bookkeeping. Each value is checked against what its setting accepts. Restore offers Restore settings too; settings
that delete or keep less history (clear on quit or lock, shorter retention) are held back and listed with Apply These
Too. A change to a carried setting is a reason to back up (`SettingsBackupManager.fingerprint`, debounced). There is no
separate settings import or export.

**Multi-device sync is designed, not built** (`SyncAvailability.isAvailable == false`, `docs/sync-design.md`): Macs
share a folder, each writes its own file and merges the others by id, content hash and tombstones. The provider's folder
sync is the transport, so `NetworkGuardTests` are unaffected.

## Consequences
- A tampered file fails authentication; offline guessing pays the KDF cost; a compromised unlocked Mac is out of scope.
- One credential restores clips, collections, snippets and preferences.
- A history that loses a little each run, or a broken store, stops the backup; a long retention period does not.
- An older Pesto reads a newer file as damaged, not newer.
- Tests: `BackupFileTests` (flips every byte, truncates at every length), `BackupKeyTests`, `BackupRoundTripTests`,
  `VerifiedBackupTests`, `TombstoneTests`, `BackupVerifyMemoryTests`, `BackupRestorePerformanceTests` (20,000 clips took
  about a minute, accepted for a one-time operation), `AutoBackupGuardTests`, `AutoBackupTests`,
  `AutoBackupServiceGuardTests`, `BackupCoordinatorTests`, `SettingsBackupSafetyTests`, `BackupSettingsTests` (UI; a UI
  test must never switch automatic backup on, since the suggested folder is the real iCloud Drive).

## Docs affected
`Sources/Core/Backup/CLAUDE.md`, `docs/sync-design.md`, `docs/guide/privacy-and-security.md`, `docs/guide/settings.md`.
