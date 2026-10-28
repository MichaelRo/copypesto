# 0016. In search, the arrow keys move between result cards and Return pastes

Status: Accepted. Supersedes only the key-handling part of [0009](0009-the-shelf-and-paste.md) (keys act on the focused card), for the search field.

## Context
With the search field active, only ↓ and ↑ moved between result cards; ← and → moved the text cursor. The shelf is a
horizontal row, so a person looking at the cards reached for ← and →, and nothing happened to the cards. Michael's
October 26 notes called this confusing.

Three options were compared:
1. **Double-Return to paste in search** (first proposed): Return would first leave the field for the grid, the second
   would paste. It costs an extra keypress on the commonest search flow (type, Return) and changes a key that works.
2. **A mode switch** (Tab or ↓ into the grid): one more concept, and Tab already moves through the filter chips.
3. **← and → move the cards too, Return keeps pasting the focused card.** No extra keypress, no new mode.

## Decision
Option 3. While the search field is active:
- **←** and **→** move to the previous and next result, as **↑** and **↓** already do, and are consumed.
- **Return** pastes the focused result (**⇧Return** as plain text), unchanged; the first result is focused by default.
- Caret editing stays in the field: any arrow with ⌘, ⌥, ⇧ or ⌃ (line start or end, word, selection) and **Home** and
  **End** reach the text field.

The cost is that a bare ← or → no longer places the caret inside the query. A person who needs that holds ⌥ or ⌘, or
selects with ⇧ and the mouse; the shortcuts guide says so. Outside search nothing changes.

## Consequences
- `KeyNavCoordinator.handleSearchMode` routes keys 123 and 124 to `onLeft` and `onRight` when no modifier is held.
- `ShelfKeyReference` lists ← → ↓ ↑ as the search entry, and `docs/guide/shortcuts.md` is updated with it
  (`ShelfKeyReferenceDriftTests`, `ShelfKeyReferenceBindingTests`).

## Docs affected
- `docs/guide/shortcuts.md`
- `docs/guide/using-pesto.md`
- `decisions/README.md`
