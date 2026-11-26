# 0078. The iPhone and iPad back up and restore by hand, through Files

Status: Accepted (owner, 2026-11-26, backlog)

Extends ADR 0010 to iOS. The file format, the key derivation and the restore are unchanged.

## Context
- The iOS history key is a this-device Keychain item (ADR 0002, ADR 0046), so an Apple device backup restored to a
  new iPhone brings the store back without the key that opens it. Sync (ADR 0018) is not a backup: a deletion on one
  device deletes everywhere, and it needs a second device.
- The Mac's backup is kept current by `AutoBackupService` in a folder it remembers. On iOS a remembered folder is a
  security-scoped bookmark that goes stale (as sync's does), and a background write is bounded by what iOS grants.
- `BackupFile`, `BackupKeyStore`, `BackupCoordinator` and `StorageService.restore` already build for iOS; the writer
  service and `SettingsBackupManager` are Mac-only.

## Decision
- **By hand only.** Settings → Data → Backup has *Back Up Now…* and *Restore from Backup…*. Nothing runs on a schedule
  and no folder is remembered. The file is written to the temporary share folder (`ShareFile.reserve`, so the lock, a
  clear and the next launch remove it) and handed to Files with `UIDocumentPickerViewController(forExporting:asCopy:)`.
  The file is named like a Mac's with the minute it was made (`AutoBackupSettings.exportFileName`), so two backups of
  one day sit side by side.
- **Keys as on the Mac.** One backup key per device in a this-device Keychain item (`BackupKeyStore`; in memory under a
  test launch). Each backup is protected by a passphrase (strong only, `PassphraseStrength`, typed twice) or by the
  recovery key alone (the header is locked with a random value nobody keeps). The recovery key is shown when the key
  is new and for every recovery-key-only backup, and *Save to Files…* waits until the person says it is stored.
  *Show Recovery Key…* asks for a fresh Face ID, Touch ID or passcode. Copying it is local-only and expires in two
  minutes (`MobileClipboard.write(protected: true)`).
- **Written by `ManualBackupWriter`** (Core/Storage, both platforms): `streamBackupRecords` into a `StreamingWriter`
  at `<file>.partial`, moved into place only after the manifest; a failure leaves neither. It refuses a history that is
  only in memory. There is no shrink guard: the file replaces nothing. Clips with secrets are left out unless the
  person includes them, a password manager's copy and clips over 10 MB always are, and each is counted.
- **No settings record.** An iOS backup carries clips, collections and deletions. A Mac backup's settings record is
  ignored on iOS, and the restore sheet says so.
- **Restore** opens any `.pestobackup` (a Mac's included) through `fileImporter`, coordinates a read first so a file in
  iCloud Drive is downloaded, opens it with `BackupCoordinator.open` (every chunk authenticated, nothing changed), shows
  the counts and the older-backup warning, and restores only after the person confirms. A background-task hold covers
  the backup and the restore. The sequence (`BackupCoordinator.sequenceKey`) moves on only when Files saved the file.
- **The type is declared.** `net.copypesto.pesto.backup` (`BackupFileType`, extension `pestobackup`, conforms to
  `public.data`) is an exported type in both apps' Info.plist, so the Files picker offers backups by name.

## Consequences
- A lost iPhone can be brought back from a file the person saved; a phone the person never backed up cannot.
- The file is as safe as the Mac's: a guessed passphrase is the attack, and only a strong one is accepted.
- A restore of a large history runs in front; if iOS suspends the app past the background grant, the restore stops
  where it was, and running it again skips what came in.
- Tests: `ManualBackupWriterTests`, `BackupFileTypeTests`, `MobileBackupTests`, `BackupTextTests`, `BackupUITests`.
  A real iCloud Drive file that is not yet downloaded, and a large restore while the app is sent away, are hand checks.

## Docs affected
- `decisions/README.md`, `AGENTS.md`, `Sources/Core/Backup/CLAUDE.md`, `README.md`,
  `docs/guide/privacy-and-security.md`, `docs/testing.md`.
- `decisions/0010-backup.md`: unchanged (accepted); this ADR adds the iOS side.
