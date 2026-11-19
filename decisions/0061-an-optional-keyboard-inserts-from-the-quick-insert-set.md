# 0061. An optional keyboard inserts from the quick-insert set; it has no typing keys and never holds the history key

Status: Accepted (owner request, 2026-11-19)

Amends ADR 0046 where it says "No keyboard extension". Extends ADR 0051 (the quick-insert set, which the keyboard reads
as AutoFill does) and ADR 0055 (the set while the History Lock is on). Everything else they decide stands.

## Context
ADR 0046 ruled out a keyboard extension for three reasons: it reaches an app's data only with Full Access, which iOS
describes as letting the developer see everything typed; it would hold a key that opens clips inside a process that
sees every keystroke; and it runs under a tight memory limit. AutoFill's text insertion (ADR 0051) became the way to put
a clip into another app.

AutoFill is a few taps deep (long-press, AutoFill, Pesto) and some fields never offer it. A keyboard is one switch of
the Globe key away in every text field. The fears of ADR 0046 hold for a keyboard that replaces the system one; they do
not hold for a keyboard that has no letters:
- A keyboard sees only what is typed on it. Pesto's has no typing keys, so what it sees is taps on its own keys (a clip,
  a starter, Space, Return, Delete). What the person types on any other keyboard never reaches it.
- The key it would hold is not the history key. The quick-insert key opens one file, the quick-insert set, which is
  already filtered (no secret, no pending, flagged or expiring clip) and already bounded (256 KB of text, read with a
  2 MB bound).
- The set is small, so the memory limit is not a risk: one sealed file, opened on demand and dropped when the keyboard
  is hidden.

## Decision
- **`PestoKeyboard`** (`net.copypesto.pesto.keyboard`, `Sources/MobileKeyboard`), a `UIInputViewController`
  (`com.apple.keyboard-service`, `RequestsOpenAccess` true). Its entitlements are the app group and the Keychain group
  `$(AppIdentifierPrefix)net.copypesto.pesto.quick-insert`, nothing else (`EntitlementsTests`).
- **What it reaches.** With Full Access, the same sealed quick-insert set AutoFill reads (`QuickInsertFile`), with the
  same key. Never the store, the history key, the inbox key or a sync key. It never reads `UIPasteboard.general`, so it
  never causes a paste prompt, and it has no network code.
- **Keys.** The clips of the set as cards, in the sections Pinned, Snippets and Recent; filters All, Pinned, Snippets
  and Recent only when two or more sections have clips (`KeyboardMenu`). A tap inserts `entry.insertionText()` (a
  snippet expanded as in AutoFill) and shows a checkmark for 0.6 s. Above them, starters that need no data: Date, Time,
  ISO Date, Weekday and UUID (`KeyboardStarter`), made at the tap through `TemplateExpander`. The bottom row: the Globe
  key (only when iOS asks for it, `needsInputModeSwitchKey`, with `handleInputModeList` for the long-press list), Space,
  Return and Delete. No search field: a keyboard cannot type into itself.
- **States** (`KeyboardMenu.State`). Without Full Access, *restricted*: the set is not even read; the starters and a
  calm note, "Allow Full Access to Insert Your Clips", which says where the switch is and that the keyboard has no
  network access. With Full Access and no set (Insert from Pesto in other apps off, or not written yet), *unavailable*:
  "Nothing to Insert Yet" and how to turn the setting on. A set with no clip, *empty*: "No Text Clips". Otherwise
  *ready*.
- **Freshness.** The keyboard re-opens the set only when its modification date (`QuickInsertFile.modificationDate`)
  shows the app rewrote it, and drops the opened set when it disappears.
- **The rules of the set are unchanged** and reach the keyboard for free: the app empties it under the History Lock
  unless "Show clips in widgets, AutoFill and the keyboard while locked" is on (ADR 0055; the setting key does not
  change, only its label), empties it on Clear History, and removes the file and the key when Insert from Pesto is
  turned off. The iOS Settings section that said AutoFill now covers the keyboard as well.
- **It stays optional.** Nothing in Pesto asks the person to add it. AutoFill remains the way to insert a clip without
  granting Full Access.

## Consequences
- The trade-off is iOS's own warning. Allowing Full Access shows a system alert that a keyboard with it can transmit
  what is typed. For Pesto's keyboard that is broader than what it does (nothing is typed on it and it has no network
  code), but Pesto cannot change the alert, and the person decides. Without Full Access the keyboard is still useful
  for the starters and says what Full Access would add.
- A second process holds the quick-insert key, as the AutoFill extension already does. Code signed by the same team
  could read the set, as before (ADR 0051); nothing else can.
- On a device: an App ID for `net.copypesto.pesto.keyboard` with App Groups (and Keychain Sharing if the profile asks
  for it), in the development and App Store profiles. App Review gets a note on why the keyboard requests Full Access.
- Hand checks on a real device (`docs/testing.md`): the Full Access alert and both states, insertion into another app,
  the Globe key and its long-press list, the History Lock and the setting turned off, and memory in Xcode's gauge.
  Core tests cover the states, the filters and the starters (`KeyboardMenuTests`, `KeyboardStarterTests`) and the
  modification date (`QuickInsertEnvelopeTests`).

## Docs affected
`AGENTS.md` (the Mobile paragraph and security invariant 2: a second holder of the quick-insert key),
`docs/ios-signing.md`, `docs/app-store-ios.md`, `docs/testing.md`, `docs/design/ios-library.md`, `docs/pictures.md`,
`decisions/README.md` and ADR 0046's status line. The README and the guide, the privacy page included, say nothing
about the iPhone app until it is released (ADR 0046); the keyboard joins them in that release.
