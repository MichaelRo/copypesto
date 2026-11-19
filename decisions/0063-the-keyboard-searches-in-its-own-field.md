# 0063. The keyboard searches in its own field

Status: Accepted (owner request, 2026-11-19)

Amends ADR 0061 ("no letter keys") and ADR 0062 (search only by the word before the caret). Everything else they
decide stands.

## Context
ADR 0062 made the word typed before switching the search: fast for one word, but it means typing into the app first,
it holds one word, and it cannot browse. Michael: real search needs a keyboard. Ask (the on-device natural-language
search the Mac and the iOS app have) needs a sentence too, and reading a sentence from the app's field would read
much more of what was typed elsewhere than one word. ADR 0061 kept letter keys out because a keyboard with letters
sees everything typed on it; that holds for letters that type into the app, not for letters that type into Pesto's own
field, where what is typed is a search the person makes in Pesto, as in the app's own search.

## Decision
- **A search key** (magnifying glass, only when the set is ready) opens the search page: Pesto's own search field on
  top (`KeyboardQuery`, at most 64 characters, gone when the page closes or the keyboard hides), the matching clips in
  one row (the first chip's clips while it is empty), lowercase letters or the numbers pad, then Globe, 123/ABC, Space,
  Delete and Done. The keyboard is 40 points taller while it is open.
- **The letters never reach the app.** `KeyboardLetters` holds only the model, whose search methods change only the
  query; the page holds no input controller (the root hands it the Globe key); `KeyboardSearchTests` scans the page,
  its keys and the model for any name of the text field. Picking a clip is
  the one thing that reaches the app: it inserts the clip, closes the page and returns or stays as Settings says.
- **The word-before-the-caret search stays**, for the quick case.
- **Ask** is not part of this decision: whether Apple's on-device model runs within a keyboard extension's memory limit
  is measured on a device first. This field is where it would take its question, so it would need no text from the
  app.
- Letters are the English layout only; a search in another script uses the word before the caret, typed on the
  person's own keyboard.

## Consequences
- App Review sees typed characters on the keyboard (the 123 pad already, now letters), which answers 4.4.1 more fully.
- What the person types on the search page is a search in Pesto; nothing of it is kept or written.
- Hand checks: the search page on a device, in a field of another app, picking a clip with each after-insert choice.

## Docs affected
`AGENTS.md` (the Mobile paragraph), `docs/design/ios-library.md`, `docs/testing.md`, `docs/app-store-ios.md` (the
review note), `decisions/README.md`.
