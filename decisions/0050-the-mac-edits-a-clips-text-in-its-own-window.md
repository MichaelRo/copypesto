# 0050. The Mac edits a clip's text in a window of its own; the shelf closes first

Status: Accepted (owner request, 2026-11-15)

Extends ADR 0048 (a clip's text can be edited), ADR 0003 (secrets), ADR 0008 (undo) and ADR 0009 (the shelf never
becomes key). Nothing they decide is reversed.

## Context
ADR 0048 gave Core one path, `StorageService.updateText(id:text:)`, and left the Mac without a way in. The shelf is a
non-activating panel that never becomes key (ADR 0009), so typing a long text inside it is not possible, and every
other window the shelf opens (Settings, the floating window) closes the shelf first and opens after it has gone.

## Decision
- **Entry:** "Edit Text…" in the card's context menu, which ⌘K also opens, and a VoiceOver action of the same name, for
  a clip `TextEditPolicy.isOffered` accepts: text, code, a link or a color that is judged, has its stored text and is at
  most 512 KB (`maxEditableBytes`; the whole text sits in one text view on the main thread). No key of its own: ⌘E is
  Show and Hide Again on the shelf, and no other conventional key is free.
- **Covered cards:** `CardMenuItem.editText` is not in the covered list, so a card covered for a screen share offers
  nothing, and a masked secret offers Edit Text only while its Show is running (the same authentication as Show; the
  editor does not ask again). If the contents become covered while the editor is open (a share starts, Hide Clip
  Contents), the editor covers its text and keeps the draft; Save waits until the cover lifts. The History Lock closes
  the editor and drops the draft.
- **The window:** a titled, resizable "Edit Text" window (`TextEditWindowController`), retained by its controller
  (`isReleasedWhenClosed = false`), hosted by `SafeHostingView(pesto:)`, monospaced for code. Save (⌘Return or ⌘S) is
  ready only for a changed text that is not blank; Cancel, Esc and the close button drop the draft. While it is open
  Pesto has a Dock icon, as for Settings. The shelf closes before it opens, as for Settings.
- **One editor:** asking for the clip already open, or for any clip while the open one has unsaved changes, brings the
  open editor forward unchanged; with nothing typed it is given the new clip.
- **Saving:** one path, `AppState.saveEditedText(id:text:)`, which calls `updateText` and maps its outcome through
  `TextEditPolicy.result(for:)`. A refusal (empty, "Another clip already has this text.", the size limit's message, a
  locked history, a failed save) is shown in the editor, which stays open; a save closes it and offers Undo the next
  time the shelf shows. ⌘Z on the shelf restores the old text and, for a formatted copy, its formatting: an edit drops the
  rich flavors (`sealText`), so a paste never carries formatted text that differs from the card.

## Consequences
- `TextEditPolicyTests` (Core), `TextEditSaveTests` and `TextEditWindowControllerTests` (hosted) and `EditTextUITests`
  pin it; `ClipTextEditTests` pins the rich flavors.
- The Undo words read "Changed the text" and "Undo Edit Text", like "Edit Snippet" and "Edit Note".
- The storage actor's save does not redraw a card by itself, so a save, and an undo or redo of a text or snippet edit,
  wait for the main context to hold the new content hash and then read the history again; the shelf gives each card
  its content hash as an inner identity (`Features/Overlay/CLAUDE.md`).

## Docs affected
`README.md`, `docs/guide/using-pesto.md`, `decisions/README.md`, `Sources/Features/Overlay/CLAUDE.md`.
