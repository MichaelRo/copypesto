# 0008. Undo and redo restore deletes and edits from sealed snapshots kept in memory

Status: Accepted

## Context
Deleting clips and collections was final: a mistaken Delete on a selection lost the clips and their pins, notes and
shortcuts, and an in-shelf confirmation was the only guard. Clip data is sealed at rest and the history can be wiped on
purpose (ADR 0002), so an undo must not become a second place where plaintext or a deleted clip outlives a wipe. The
shelf also has a performance budget (open under 100 ms, memory under 150 MB).

## Decision
1. **What can be undone:** every change a person makes to a clip or a collection: deleting clips or a collection;
   editing a clip (title, note, tags, icon, collection, pin, paste shortcut, sensitive mark, expiry, its place in a
   collection); dragging a clip to a collection chip; creating, editing, duplicating and reordering collections,
   including a smart collection's rule; adding a snippet and editing its text; and importing snippets, a collection
   file or a library. Cmd-Z undoes the newest action and Shift-Cmd-Z redoes it, in the shelf's grid and in an empty
   search field; a text field with text keeps them for its own text. In Settings the Edit menu's Undo and Redo do the
   same, named for the action ("Undo Delete 3 Clips").
2. **A banner** reads "Deleted 3 clips · Undo" for a delete from the shelf, and VoiceOver announces it. A delete that
   cannot be undone shows none, and the delete question says which it is ("You can undo this with ⌘Z" or "This can't be
   undone") from the same policy.
3. **The stack is in memory only** (`UndoHistory`): at most 20 entries and 16 MB (`UndoPolicy.maxEntries`,
   `maxHeldBytes`); past either, the oldest goes first. It holds the clip's stored, still sealed bytes
   (`ClipSnapshot`), never plaintext, and never writes to disk.
4. **Restore is a re-insert under the same id**, not a soft-delete flag, which would touch every read of the history.
   The tombstone a user delete writes is removed on undo and written again on redo. A clip copied again meanwhile (same
   content hash) is not duplicated; a paste shortcut another clip took stays with it; a collection whose name was taken
   returns with a numbered name.
5. **Edits are undone field by field**, so a background change to the same clip (a count, a newer preview) is left
   alone; an edit that changes nothing records nothing. A collection change holds the collection before and after
   (`CollectionStore`); a snippet's new text holds the clip's sealed content before and after. An addition is taken
   back without a tombstone, so it can be imported again.
6. **What is never held** (`UndoPolicy`): a clip that expires on its own (burn after paste, a kept password-manager
   copy), a credential, one still being analyzed, one over `maxClipBytes` (4 MB, judged from the plain `byteSize`
   column), and a batch of more than `maxClipsPerEntry` (200) clips. A batch with one such clip is deleted for good as a
   whole; an import over 200 clips or with such a clip is not undoable.
7. **Not undoable by design:** Clear History and Clear Everything, retention and clear-on-quit deletions, a restore from
   a backup, appending by a second Cmd-C, a paste, and what Pesto changes on its own (picture screening, link previews,
   the search vector). These record nothing.
8. **Every path that wipes history calls `undoHistory.clear()`:** Clear History, Clear Everything, key recovery and
   locking the history, which also takes the banner down. Undo and redo do nothing while the history is locked.

## Consequences
- A deleted clip's sealed bytes stay in memory until the stack passes its limits, the person locks or wipes, or the app
  quits. After a relaunch a deleted clip is gone for good.
- A new column on `ClipboardItem` or `Pinboard` must be copied by `ClipSnapshot` / `PinboardSnapshot`
  (`ClipDeleteUndoTests` fails until it is).
- The shelf is a panel that never becomes key and so never sees the Edit menu's key equivalents: `KeyNavCoordinator`
  handles its keys, and the Edit menu serves the Settings window and leaves a text field its own undo (`EditMenuUndo`).
- Nothing runs on ingest, search, scroll or opening the shelf. `make bench-undo` (`UndoPerformanceTests`,
  `UndoHistoryMemoryTests`) measures recording, restoring, editing, a reorder of 200 clips, the copy path with a full
  stack and the stack's memory at its limits; the numbers are in `docs/perf/undo-2026-10.md`.
- Rejected: a soft-delete flag with a trash (clips stay on disk longer than asked, and about 86 read sites change);
  persisting the stack (it would outlive a lock, a quit and a wipe); undo for Clear History (too large, and the wrong
  thing to keep after a person asked to clear).

## Docs affected
`AGENTS.md`, `docs/guide/shortcuts.md`, `docs/guide/using-pesto.md`, `docs/guide/privacy-and-security.md`,
`docs/feature-reference.md`, `docs/perf/undo-2026-10.md`, `Sources/Core/Storage/CLAUDE.md`,
`Sources/Features/Overlay/CLAUDE.md`, `CHANGELOG.md`.
