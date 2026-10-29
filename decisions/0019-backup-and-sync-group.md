# 0019. Settings → Data shows backup and, later, sync as two switches in one group, with one place for where the copies live

Status: Accepted

Supersedes the Settings wording of [0010](0010-backup.md) ("Data opens with the backup status row", the Backup section's buttons) and the pane layout line of [0012](0012-settings-and-shortcuts.md); the backup file, its guards and its keys are unchanged. Sync itself is [0018](0018-multi-device-sync.md) (not built); nothing here makes it visible.

## Context
Backup sat last on a long Data page, below text clean-up. Its state was a dot and a headline ("Backup is off"), the fourth stat tile said only "Off", and its automatic toggle read "Keep it up to date automatically", which is how sync sounds. A person asked whether the backup syncs; the answer ("no, a second Mac can only restore the file, which merges clips in") took a paragraph. Sync will need its own state, key, Reset and Leave, and must not read as a second backup.

Research ([`docs/research/backup-and-sync-settings-ux.md`](../docs/research/backup-and-sync-settings-ux.md), 2026-10-29; sources and gaps are in it) found no industry convergence on one layout or two. It found one consistent rule: products define backup and sync apart and state the delete consequence in the same sentence (a backup is a copy to restore from; sync keeps devices matching, so a delete reaches all of them). No product surveyed offers a user toggle to keep secrets out of sync, and none uses the phrase "keep it up to date automatically" as a label.

## Decision
- **One group, two switches with different verbs.** "Back up this Mac" now; "Sync with my other Macs" only when `SyncAvailability.isAvailable`, off by default, per Mac, never nudged. Each says what it is not: a backup never changes another Mac; sync is not a backup and a delete reaches every synced Mac.
- **A summary under the stat tiles:** "Your clips stay on this Mac." and one status chip per feature, all from preferences (a pane never reads the Keychain). The fourth tile says what is true: Off, Not yet, the time of the last backup, Paused, or Needs you.
- **"Needs you" has a source:** `AutoBackupSettings.problem` (`folderMissing`, `failed`, `refused`), written by `AutoBackupService` after each run and cleared by a written backup. It is not part of the settings backup (`SettingsBackupManager.rules`), so it cannot start a backup loop.
- **Where the copies live is one row.** Backup shows its folder with Show in Finder and Change…; sync will use the same row and folder rules. Change… (`AutoBackupService.changeFolder`) writes the backup in the new folder first and remembers the folder only when that write is accepted, so a missing folder, or one that holds a backup this Mac's key does not open, leaves the old folder in place and the other file untouched. The old file stays where it was for the person to delete. It is also the way out of "Folder Missing".
- **What goes where is honest.** Core has no per-category choice: a backup always carries clips (with pins and snippets), collections, deletions and this Mac's settings. The page lists that in one line and offers the one real control, "Include clips with secrets" (`includesSecrets`, behind the authentication window); sync's column and its secrets choice arrive with sync (0018: secrets off by default).
- **Turning it on stays a sheet.** A switch cannot choose a recovery key or a passphrase, show and confirm the key, or pick the folder. The switch opens the Set Up sheet; turning it off asks first and leaves the file in its folder (the meaning of the old Remove Backup). The sheet's last toggle is "Back up automatically" (default on; a few minutes after a copy, at most once an hour); the page shows "Only when you choose Back Up Now" when it is off.
- **Restore says what it will do before it does it.** Restore from Backup shows "Up to N clips would be added, M were already here", plus clips kept deleted and clips the backup's own deletions would remove, from `StorageService.previewRestore`, which follows `restore`'s order and writes nothing. It is an upper bound: a picture like one already here is only recognized when stored.
- **Not changed:** the backup file, the guards (`AutoBackupGuard`), the keys, Clear Everything's keep-or-delete choice, the restore merge rules, and that no UI test turns a backup on (the suggested folder is the real iCloud Drive).

## Consequences
- The page is shorter to read and the difference to sync is on the page. The cost is that the switch hides a sheet; the sheet's title and the switch label ("Back up this Mac") are therefore both searchable (`SettingsIndex`).
- `BackupStatusRow` is gone; its states are `BackupChip` (Core) and the status line.
- Per-category choices are a known gap, recorded here so the sync work (0018) designs them once for both.
- The Settings strings, the guide, the README and the website pages change together (below), and `docs/images/settings-data.png` is retaken.

## Docs affected
- `README.md`, `docs/guide/settings.md`, `faq.md`, `moving-from.md`, `privacy-and-security.md`, `troubleshooting.md`, `docs/feature-reference.md`, `docs/copy-guide.md`, `docs/design/website-shelf-spec.md`, `CHANGELOG.md`
- `Sources/Features/Settings/CLAUDE.md` and `Sources/Core/Backup/CLAUDE.md` (the chip, the problem key, the preview)
- `decisions/0010-backup.md` and `0012-settings-and-shortcuts.md` are not edited; their status lines point here
- The website (a separate repository): the synced guide pages and picture, and its privacy, features, security and ledger pages
