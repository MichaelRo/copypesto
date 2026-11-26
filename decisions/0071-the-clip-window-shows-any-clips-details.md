# 0071. The Clip window shows any clip's details, and edits its text when Edit Text would

Status: Accepted (owner pick, design board 3b, 2026-11-25: "just make sure title is editable as well")

Amends ADR 0050 (the Edit Text window). What may be edited, the 512 KB limit, a covered card offering nothing and
one Undo for an edit stand.

## Context
Field notes: the Edit Text window was "very ugly and unconvenient", a bare text box for text clips only, while a
clip's title, note and tags were each edited in a popover of their own from the card's menu. iOS already has a
details screen for every clip (`ClipDetailView`). The board drew two layouts; the owner chose the two-pane one.

## Decision
- **One Clip window for every clip**, opened by **Show Details…** in the card's menu or **⌘I** on the focused card
  (`ShelfCommand.showDetails`), and by Edit Text… as before; the shelf stays open behind it.
- **On the left**, the title (editable, saved on Return or when it loses focus), then the content: the whole text to edit
  when Edit Text would be offered (ADR 0050), with Revert and Save while it is changed and Close (Esc); any other clip
  (a picture, a file, a secret not shown) shows as its hover card does. Save still closes the window.
- **On the right**, the note, the tags (each with a remove button; several may be typed at once), the collection,
  Pinned and the facts, each saved as it changes through `ClipEditor`, so ⌘Z on the shelf takes it back.
- **A secret's text is read only through Edit Text**, which its card offers after a Show with Touch ID; Show Details
  and ⌘I never decrypt it (the grid's reveals of a covered card ask for nothing, so they cannot count).
- **The window obeys the card's cover** (`CardConcealment`): a picture the content filter blurs, a hidden secret or a
  clip still being judged shows its facts only; a hidden secret's title and note are hidden; while clip contents are
  covered the whole window is covered, and a typed draft waits.
- **Only what the person changed is saved** (`ClipDetailsEdit.personChanged`), so closing the window after the clip
  changed on its card or through sync never writes an old value back; nothing is saved for a deleted clip or after
  the History Lock.
- **The rules for what is saved are Core's `ClipDetailsEdit`** (a blank title or note is none; a tag loses a leading
  `@` or `#` and is kept once whatever its case), shared with the iPhone's details form.

## Consequences
- The card's Add Note, Add Tag and Rename popovers remain for a quick change; the window is where everything is.
- A larger preview of a picture or file in the window, and Make Snippet with fill-ins, are backlog.
- The UI tests open the window through Edit Text as before; the new fields are a hand check until a UI test covers
  them.

## Docs affected
- `docs/guide/using-pesto.md`, `docs/guide/shortcuts.md`, `README.md`, `decisions/README.md`
