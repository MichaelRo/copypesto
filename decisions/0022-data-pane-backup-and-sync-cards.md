# 0022. Settings → Data gives backup and sync a card each, and drops the Backup stat tile

Status: Accepted

Supersedes the layout lines of [0019](0019-backup-and-sync-group.md) ("one group, two switches", "the fourth tile says what is true"); the backup file, its guards, sync and every setting are unchanged. 0019 is not edited.

## Context
A design review of the Data pane picture found "Backup: Off" three times (a stat tile, a chip, the switch), the sync warning ("Deleting a clip on one Mac deletes it on all. Sync is not a backup.") as a footnote under a shared switch group, and a Backup switch beside a Set Up Backup… button that did the same thing. In the code the backup switch cannot turn anything on by itself: on opens the Set Up sheet and Cancel leaves it off (`show(.setUp)`; the UI test `test_theBackupSheet_keepsSetUpDisabledUntilAFolderIsChosen_andCancelLeavesNothingSetUp` pins it). Sync's switch is the same (`beginSetUp()`).

## Decision
- **The stat strip has Clips, On disk and Oldest clip.** The Backup tile is gone; the chips under "Your clips stay on this Mac." already say backup and sync. `BackupChip.tileValue`, `tileLabel` and `tileTint` are removed.
- **Backup and Sync are two cards (two form sections), each a switch, one sentence and its actions.** Sync's off card gains *Set Up Sync…* (the same action as its switch), so both read alike. Sync leads with a bold line that states the consequence ("Deleting a clip on one Mac deletes it on all.") and a caption that says it is not a backup. The warning is always shown, because it is the text a person reads before turning sync on; its icon is neutral. Only when sync is on and this Mac has no backup does the icon turn red and a line say so ("This Mac has no backup. Set Up Backup… keeps a copy you can restore from."), because that is the one state with no way back. A backup is rewritten after a synced delete (the previous file is kept once), so the line promises a copy, not that a deleted clip can always be restored.
- **The switch stays a launcher, and says so.** The off Backup sentence now says that turning it on asks for a folder and a way to unlock the file first. A disabled switch was rejected: it would leave the person with no obvious way to start from the switch, and it would hide the one control a VoiceOver user finds first.
- **"What goes where" has its own card, and the closing note** "Nothing leaves this Mac until you set this up. Clips with secrets stay out unless you choose." stays as the last footer of the group.

## Consequences
- The two scary facts (a delete reaches every synced Mac; a backup never changes another Mac) sit in the card they belong to.
- The picture `docs/images/settings-data.png` must be retaken (`make pictures`).

## Docs affected
- `docs/guide/settings.md`; `README.md` needs no change (it names no tile).
- `docs/images/settings-data.png` and the website's copy of it (separate repository).
- `decisions/0019-backup-and-sync-group.md` is not edited.
