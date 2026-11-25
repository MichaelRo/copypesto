# 0066. The keyboard searches in the person's own languages and looks like iOS's keyboard

Status: Accepted (owner picks on the design board, 2026-11-25)

Amends ADR 0063 ("Letters are the English layout only"; one row of 58 pt results; Done in the field row) and ADR 0062
(the size pill and the gear in the chip row; Search in the bottom row). Everything else they decide stands: the
letters type only into Pesto's own field, a pick is the one thing that reaches the app, the word before the caret is
read only with Full Access and never kept.

## Context
Field notes (2026-11-22): the search page felt unlike an iOS keyboard (small lowercase keys, no shift, no accents)
and a Hebrew speaker with an English phone saw it in the wrong direction. The owner: searching in one's own language
and layout is a must. The design board (2026-11-25) drew the shelf and the search page as iOS draws its keyboards;
an Opus designer critique and the owner's picks settled the details.

## Decision
- **Layouts are data in Core** (`SearchKeyboardLayout`, `SearchKeyboardLayouts`): QWERTY, Spanish, AZERTY, German,
  QWERTZ, Swedish/Finnish, Danish, Norwegian, Turkish, Russian (and the Cyrillic languages without their own), Ukrainian,
  Greek, Hebrew, Arabic, Persian, Korean, Thai (Kedmanee) and Hindi (InScript), each with its rows, a shift layer where
  the script has one, iOS's long-press accents and where Delete sits (Hebrew's on the top row). The page offers the
  layouts of the person's own keyboards (`UITextInputMode.activeInputModes`), then their preferred languages, then
  QWERTY. Holding the space bar, which names the layout's language, moves to the next one; the globe stays iOS's.
- **Japanese and Chinese are named, not faked.** They need an input method a keyboard extension cannot host inside
  its own field; the field's placeholder says so, and the other layouts still work.
- **Korean composes** (`HangulComposer`): jamo join into syllables as on iOS's two-set keyboard, a final moves to the
  next syllable before a vowel, and Delete takes back one jamo (`KeyboardQuery.type(_:composingHangul:)`).
- **Keys follow iOS's metrics** (`KeyboardSearchMetrics`): 42 pt keys on an iPhone in portrait, 52 pt on iPad, 6 and
  8 pt gaps, 5 and 7 pt corners, a 1 pt shadow, a callout over a held key, accents on a longer hold, Shift once and
  caps lock on a double tap. The letter area has one height, so a four-row script gets shorter keys.
- **Results sit on a tray** whose rows follow the keyboard's size: one row at Small (140 × 64) and Medium
  (150 × 88), two at Large (140 × 78), one in landscape and five larger cards on iPad. Return on the search page is
  Done. On the shelf, a word search rings its first match and Return reads Insert and inserts it.
- **The shelf** keeps the library's chips, puts Search on a round key beside them and uses iOS's bottom row (123,
  globe, space, delete, return). The size pill and the gear leave the chip row; a Pesto chip at its end opens settings
  inside the keyboard (the size, with the cards previewed at it, and the way to Pesto's Settings).
- **AutoFill's gear** opens Keyboard & AutoFill, through the same responder-chain opener the keyboard uses
  (`HostURLOpener`); whether either works on a device is a hand check.

## Consequences
- The search page is taller: 340 pt at Small to 438 pt at Large on an iPhone in portrait (284 pt was the floor).
- A homemade letter keyboard is compared key by key with Apple's; it has no autocorrect, swipe or dictation, and
  that is accepted: it types a search, not prose.
- Hebrew's Delete position and the Thai and Hindi rows are copied from the standard layouts, not measured on a device.
- `HostURLOpener` reaches `UIApplication.open` through the responder chain, which App Review may question (guidelines
  2.5.1, and 4.4.1 for keyboards); AutoFill asks `extensionContext.open` first and uses the chain only when that opens nothing. If review objects, the
  gear and the Pesto chip fall back to saying where the settings are.
- Belarusian, Kazakh, Kyrgyz, Tajik, Mongolian, Bulgarian, Serbian and Macedonian share the Cyrillic grid with their
  own letters on long presses (review, 2026-11-25); Serbian in Latin script gets QWERTZ.

## Docs affected
- `docs/design/ios-keyboard.md`, `docs/design/ios-library.md` (the keyboard section)
- `docs/testing.md` (device checks: the AutoFill gear, layouts on a phone with several keyboards)
- `decisions/README.md`
