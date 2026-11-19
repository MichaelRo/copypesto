# 0062. The keyboard is a small shelf with chips and a word search

Status: Accepted (owner request after a design consult, 2026-11-19); its search is extended by ADR 0063 (a search page
with letters that type only into Pesto's own field)

Amends ADR 0061 (the keyboard's layout, and its promise about text typed elsewhere) and ADR 0051 (what the
quick-insert set carries). Everything else they decide stands.

## Context
The first keyboard (ADR 0061) listed the clips in a vertical grid under section headers, with no search: a keyboard
cannot use another keyboard to type into a field of its own, and Pesto's has no letter keys. A designer and a daily
user reviewed it: two clips fit on an iPhone, the headers took a quarter of the height, and with 40 pinned clips there
was no way to find one. Both preferred the Mac shelf's shape (a row that scrolls sideways, chips on top), and both
chose, of the ways to search, the word the person just typed on their own keyboard: it is text expansion, which people
know, and it needs no letter keys. A letters page that types only into Pesto's own field was rejected: once Pesto has
letter keys it is a typing keyboard, and "it only types into its own field" is a promise no one can check.

## Decision
- **Shape.** A row of cards that scrolls sideways, two rows high on iPhone (filled column by column) and one on iPad,
  each card a small Pesto card with the kind's glyph and a laptop when it was copied on another device. Above it, chips
  as on the Mac shelf: Recent, Pinned and Snippets when they have clips, then the collections the person chose, in their
  order. The section headers are gone.
- **The person chooses.** iOS Settings → AutoFill and keyboard → Collections picks and orders up to 12 collections
  (`Setting.keyboardCollections`); "After inserting a clip" chooses Return to my keyboard (the default) or Stay in Pesto
  (`Setting.keyboardReturnsAfterInsert`). A long press does the other. The keyboard cannot read Pesto's preferences
  without Full Access, so both travel in the sealed set (`QuickInsertSet.collections`, `returnsAfterInsert`).
- **The set carries collections.** Each chosen collection's clips, up to 30, in its own order, as ids of the set's
  entries; a clip already in the set is listed, not carried twice; one carried only for a collection is in the section
  `collection`; all of it shares the set's 256 KB. Only a pinned clip with placeholders is a snippet, so a collection's
  other clips insert as they were copied. A set written before this opens with no collections and returning after an
  insert. AutoFill lists the chosen collections under their names after Recent.
- **Search by the word before the caret** (`KeyboardWord`). With Full Access, the keyboard reads the text before the
  caret from `textDocumentProxy` and keeps only its last word, 2 to 32 characters, and only when the caret sits at its
  end. It shows as the first chip in quotes; the cards are the clips whose title starts with it, then those that hold
  it. Picking one deletes the word and inserts the clip. With no match the chip dims and the chosen chip's clips show;
  its × drops the search.
- **What this changes in ADR 0061.** That decision said what the person types on another keyboard never reaches Pesto's.
  The last word before the caret now does: read from the field when the keyboard appears or the text changes, held in
  memory to filter, never written, logged or sent, and only with Full Access (without it there is no set to search).
  Nothing else typed elsewhere is read.

## Consequences
- A clip copied on a Mac is marked, so "copy on the Mac, insert on the phone" can be seen; Recent is newest first, so
  the latest copy from anywhere leads.
- The keyboard still has no letter keys, never reads the clipboard and makes no network request.
- Capture on iOS stays the person's act (share sheet, "Add Clipboard to Pesto" from Control Center or Back Tap); a
  Save Selection key waits on a spike of `selectedText` in the main apps.
- Tests: `QuickInsertCollectionsTests` (chosen order, no repeats, bounds, the after-insert choice, other-device mark,
  an older set's defaults, the stored ids), `KeyboardMenuTests` (chips, collection order, search ranking),
  `KeyboardWordTests` (when there is a word, how many deletes), `KeyboardRenderingTests` (the shelf and the search,
  light and dark). The word on a real field, and the replace, are hand checks on a device.

## Docs affected
`AGENTS.md` (the Mobile paragraph), `docs/design/ios-library.md`, `docs/testing.md` (the keyboard on a device),
`docs/app-store-ios.md` (the review note), ADR 0061's index line.
