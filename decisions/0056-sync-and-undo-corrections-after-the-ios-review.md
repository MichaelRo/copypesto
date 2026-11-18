# 0056. A remote edit replaces a clip's text in place; undo, withdrawal and the echo guard follow ids; an iPhone holds its folder per holder

Status: Accepted (review of the iPhone and iPad branch, 2026-11-18)

Corrects ADR 0053 where it says an older Pesto "loses nothing" and where it lists the undo of a deletion as a limit.
Extends ADR 0008 (undo), ADR 0018 (sync), ADR 0046 (iPhone and iPad) and ADR 0053. Nothing else they decide changes.
The sync format does not change.

## Context
A review of the iPhone and iPad branch found places where a clip was still treated as its text after ADR 0053, and
places where an iPhone's sync outlived the moment it was allowed to run:
- A known clip that arrived with new text was deleted and inserted again, which wiped what only this device keeps about
  it: its ⌘1–9 slot, paste days, remembered fill-ins, capture method (ADR 0049), source colour and place.
- Undo of the delete of one of two clips with one text did nothing, because any clip with the hash counted as "back".
- A synced clip edited into a secret was withdrawn with the hash of its new text, so the secret's hash left the device.
- Sync's own insert was counted as the latest local copy, so a real copy of that text within two seconds was swallowed
  by the echo guard (and a double ⌘C could drop the synced clip as its echo).
- A background refresh's end suspended sync even when the app had come back to the front meanwhile; when iOS ended the
  background time, the pass ran on after the folder's security scope ended; a stale bookmark went straight to repair.
- ADR 0053 says an older Pesto applies an edit by text "and loses nothing". It does lose: an older device gives the
  edited clip A's curation (title, note, tags, pin, collection) to B, the clip that already held the text, and B keeps
  it; when that older device later changes B, its record carries A's curation to every device.

## Decision
- **A remote text edit is applied in place.** A clip held here under the record's id, with a later stamp and a text
  record, has its text replaced through the path an edit takes (`StorageService.replaceText`: sealed, judged, hashed
  again, its vector and signature redone, a link's preview dropped), with the remote stamp and curation in the same
  save and no Undo. Everything this device keeps on its own stays. A payload that is not text keeps the old path.
- **Undo restores by id.** A deleted clip's snapshot names the clips that held the same text and stayed
  (`ClipSnapshot.textAlsoHeldBy`); restore skips it only when its id is back or when a clip holding the text is not one
  of those, which is a copy made after the delete.
- **A withdrawal names only the id.** The clip's present text is what must stay here, so not even its hash leaves.
- **The echo guards belong to this device's copies.** After sync inserts a clip, the two-second guard and the double ⌘C
  echo are put back to what they were before it.
- **An iPhone holds its folder per holder** (the app in front, a background refresh). Sync is suspended and the folder
  let go only when the last holder is done. Stopping the folder service cancels its pass; the pass checks between its
  steps, batches and segments, and `applySync` between records, so a segment applied in part is never marked as read.
  The background task's expiration drops the background hold and reports the task done once, with success false.
- **A stale bookmark that still opens the folder is made again and stored** (Apple's pattern); only one that cannot be
  renewed, or does not resolve, is a repair.
- **An older Pesto is a known limit, not a loss-free one**: until every device runs a version with ADR 0053, an edit that
  gives a clip another clip's text can move curation between the two on the older device and from there to the others.

## Consequences
- `SyncTextEditTests` (in-place edit keeps local state, id-only withdrawal, the echo guard, 300 deletions name the text
  only where none stays), `ClipDeleteUndoTests`, `SyncCancellationTests`, `SyncFolderBookmarkTests`, `MobileSyncTests`
  and `SyncExchangeTests` pin it; `SyncFormatTests` and `SyncMergeTests` are unchanged and green.
- A device that first meets two clips with one text from the folder still folds them into one (ADR 0053): telling an
  edited twin from two devices' copies of the same words needs a field the format does not have.
- On the Mac, stopping sync (Leave Sync, a folder change) now also ends a pass that is running.

## Docs affected
`Sources/Core/Sync/CLAUDE.md`, `decisions/README.md`.
