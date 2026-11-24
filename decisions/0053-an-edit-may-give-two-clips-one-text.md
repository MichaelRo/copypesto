# 0053. An edit may give a clip the text another clip holds; both stay, on every device

Status: Accepted (owner request, 2026-11-18: "we need to enable the user edit whatever he likes"); corrected for undo and older builds by ADR 0056

Supersedes the refusal in ADR 0048 ("a text another clip already holds", `sameAsAnother`) and the "Another clip already
has this text." message of ADR 0050. Everything else they decide stands. Extends ADR 0008 (undo), ADR 0010 (backup) and
ADR 0018 (sync).

## Context
`updateText` refused a text another clip held, because the history kept one clip per content and sync treated one plain
SHA-256 as one clip. Checked what two clips with one text actually break:
- **Ingest** found "the" duplicate with an unsorted fetch, so a fresh copy of that text moved an arbitrary one of them.
  A new snippet of that text pinned an arbitrary one too, and a search vector was stored on the first clip with the
  hash, so the edited clip could stay without one.
- **Sync apply** looked for a clip with the record's text before its id: the record of the edited clip A (now B's text)
  gave A's title and pin to B, and A kept its old text on the other device. The replace path re-ingested through the
  duplicate check, so a clip whose new text another clip held there was lost.
- **A deletion** carried the plain hash, so deleting A removed B on every other device.
- **Undo and Redo** skipped a clip whose target text another clip held, so a step did nothing.
- **Backup restore** counted a clip as already here when its text was, so only one of the two came back.
- Nothing hash-like is `@Attribute(.unique)`; the collection-file and Paste importers read external data and still fold
  repeats, which is right for them.

## Decision
- **An edit may produce any text** but an empty one or one over the size limit. `TextEditOutcome.sameAsAnother` and both
  apps' messages for it are gone.
- **A fresh copy of a text two clips hold moves the one used most recently** (latest `timestamp`, then the higher
  sequence number), and only that one; the other stays where it is. A new snippet of that text pins the same one
  (`StorageService.holding(_:)` is the one order). A search vector is stored on the clip it was computed for.
- **Sync matches a record by id first.** A clip this device holds under the record's id is that clip: its curation is
  applied when the text is the same, and its text is replaced (without the duplicate check) when the record is later
  than the clip's own stamp. Only a record whose id this device does not hold is matched by text, as two devices'
  copies of the same words always were.
- **A deletion names only the id while another clip here still holds the text** (the tombstone's `plainHash` is left
  out, as it already is for a secret); the last clip with that text is deleted with its hash, as before.
- **Undo and Redo apply** whatever another clip holds.
- **Restore** brings back every clip of the backup that is not here by id, or by text outside what this restore brought
  back.
- **The sync format does not change**: no record, field or version is added; a tombstone without a hash was already
  valid.

## Consequences
- `DuplicateTextTests`, `ClipTextEditTests` and `SyncTextEditTests` (two devices: both clips stay under the same ids, a
  deletion removes only its clip, a later edit changes only its clip) pin it; `SyncMergeTests` and `SyncFormatTests` are
  unchanged and green.
- A device that meets both clips for the first time from the folder (a new device, or one that never held the edited
  clip under its id) still folds them into one, as two devices' copies of the same words fold; the folded clip comes
  back as two only if one of them is changed again. An older Pesto applies the edit by text, as ADR 0048 feared, and
  gives the edited clip's curation to the other one; it loses nothing.
- Undo of a deletion still skips a clip whose text another clip holds (`restore` in the undo path), so deleting one of
  two clips with one text and undoing leaves the one that stayed.
- Pesto's history can show two cards with the same text when the person makes it so.

## Docs affected
`docs/guide/using-pesto.md`, `Sources/Core/Storage/CLAUDE.md`, `Sources/Core/Sync/CLAUDE.md`, `decisions/README.md`,
the status lines of ADR 0048 and ADR 0050.
