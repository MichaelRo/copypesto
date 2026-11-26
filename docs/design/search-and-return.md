# Search and Return, everywhere

What each surface does with search and with Return, read from the code on 2026-11-25. "Before" is `main`; "After" is
what PR #205 (ADR 0066) changes. Use this table before touching a key handler: the same key means different things
on purpose in some places, and those are listed at the end.

## The Mac shelf

| State | Key | What happens | Where |
|---|---|---|---|
| Cards, no search | Return | Pastes the focused card; with two or more selected, pastes them one by one | `KeyNavCoordinator`, `GridView+Actions` |
| Cards | ⇧Return | Pastes the focused card as plain text | same |
| Cards | ⌘Return or ⌘E | Shows or hides a covered clip | `ShelfCommand` |
| Any | ⌘1 to ⌘9 | Pastes the Nth card | `ShelfCommand` |
| Cards | Click, double click | A click focuses, a double click pastes (ADR 0009) | `ShelfActions` |
| Cards | Space | Toggles selection of the focused card (not Quick Look) | `GridView+Actions` |
| Any | ⌘Y | Quick Look, not on a covered clip | `ShelfCommand` |
| Cards | ⌘F, or typing a letter | Opens the Find bar; a typed letter starts the query | `KeyNavCoordinator`, `AppState+FilterChips` |
| Cards | Esc | Cancels Touch ID, then closes Quick Look, the hover card, the selection, then the shelf | `GridView+Actions` |
| Cards | ⌫ | Asks before deleting; Return confirms, Esc cancels | `GridView+SelectionBar` |
| Locked | Return | Unlocks | `KeyNavCoordinator` |

## The Mac Find bar

| State | Key | What happens | Where |
|---|---|---|---|
| Results | Return | Pastes the focused result (the first is focused, ADR 0016) and saves the query to history | `GridView+Actions` |
| Empty query, no filters | Return | Nothing is pasted | same |
| No results, the text reads like a question | Return | Runs Ask Pesto | `AskHeuristic` |
| Any | ⌘Return | Runs Ask Pesto | `KeyNavCoordinator` |
| Results | ⇧Return | Pastes the focused result as plain text | same |
| Any | Arrows | Bare arrows move between results; with ⌘, ⌥ or ⇧ they move the caret (ADR 0016) | `KeyNavCoordinator` |
| Any | Tab | Moves through the filter chips; Return or Space toggles one | same |
| Any | Esc | Releases the chip cursor, closes the date row, else closes Find and clears it; a second Esc acts on the cards | same |

The floating window shares the grid and the Find bar: a click or Return copies (copy-only) or pastes in place. **Known
bug:** Return in its Find bar ignores copy-only and takes the shelf's paste route (`GridView+Actions.selectItem`);
fixed with the Find bar change (PR 1). The quick menu (at the cursor) takes clicks only; its Esc also reaches the app
underneath (a global monitor), noted, not changed.

## The iPhone and iPad library

| State | Key | What happens | Where |
|---|---|---|---|
| Search field | Return | Runs Ask only when nothing matched and the text reads like a question; otherwise nothing (it never copies the first result) | `PhoneLibraryView`, `PadLibraryView` |
| Searching, text typed | ⌘Return (keyboard) | Runs Ask | same |
| A focused card (keyboard) | Return | Copies it, or toggles it while selecting | `ClipCard` |
| Any | ⌘F | Opens search | `LibraryCommands` |

## The Pesto keyboard

| State | Key | Before (`main`) | After (#205) |
|---|---|---|---|
| Shelf, a word typed before switching (2 to 32 letters) | Chips and cards | A chip with the word in quotes, and the clips that match it; a tap inserts a clip and replaces the word | Unchanged |
| Shelf, a word with matches | Return | Types a new line | **Insert**: inserts the first match, replacing the word; that card is ringed. A picture is never ringed and never inserted (it is copied by a tap) |
| Shelf, no word or no match | Return | Types a new line | Types a new line |
| Shelf | Search | A magnifier key in the bottom row | A round key beside the chips |
| Search page | Typing, Delete | Letters (one layout) type only into Pesto's own field; Delete in the bottom row | The person's own layouts, Shift, accents; Delete in the letter rows |
| Search page | Return | There is no Return key; Done closes the page | Unchanged: Done closes the page (on iPad it sits where Return is); it never inserts |
| Search page | A result | A tap closes the page and inserts the clip; a picture is copied | Unchanged |

So **Return inserts only on the shelf, and only when a word you typed has a match.** Everywhere else on the keyboard
it types a new line (shelf) or there is none (search page).

## AutoFill and snippet prompts

| Surface | Return | Where |
|---|---|---|
| AutoFill picker, search field | Ends editing; a tap on a card inserts it | `InsertPickerView` |
| Mac snippet prompt | In a one-line field, pastes at once; in a multi-line field, a new line; ⌘Return pastes | `FillInPromptView` |
| iPhone snippet sheet | Done in a one-line field copies; in a multi-line field, a new line; ⌘Return copies | `SnippetFillSheet` |
| AutoFill snippet sheet | Done in a one-line field inserts; ⌘Return inserts | `InsertPickerView` |

## Where the same key differs, on purpose or not

- **Return in search**: the Mac pastes the focused result; iOS never copies a result (a tap does). On purpose: the
  Mac shelf is a keyboard tool, the iOS library is touch-first.
- **The keyboard's Return** inserts only on the shelf with a word match (#205); the search page has no Return.
- **Snippet prompts** finish on Return from a one-line field everywhere: the Mac pastes, the iPhone copies, AutoFill
  inserts.
- **Space** toggles selection on the Mac shelf; on the keyboard's search page a hold switches layout.
