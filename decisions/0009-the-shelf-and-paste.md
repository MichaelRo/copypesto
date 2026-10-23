# 0009. Paste waits for the target's keyboard, a click focuses and a double click pastes, and the hover card is a window of its own

Status: Accepted

## Context
Choosing a clip should land it in the previously frontmost app without a manual ⌘V, and nothing should land by accident.
A synthesized ⌘V depends on the target being frontmost and key at that instant, behaves oddly in some apps (Electron,
games) and needs Accessibility, which a person may decline. The shelf is a non-activating panel, so after it closes the
target is frontmost but not yet key; a ⌘V posted too early is dropped silently. A fixed sleep covered that at a cost of
over half a second per paste.

A single click that pastes sends text into another app on a stray click or when selecting cards for Delete. A transient
`NSPopover` for the hover card could not be reached with a pointer, drew glass on glass, ignored Reduce Motion, and
swallowed the click that dismissed it.

## Decision
**Paste has three tiers; each failure falls through quietly** (`PasteCoordinator.executePaste`):
1. **Accessibility direct write** of text into the target's focused element (`AccessibilityWriter`, off the main actor).
   Skipped for non-text clips, an unsettable value, no Accessibility, and text over 200,000 bytes
   (`PasteCoordinator.directWriteLimit`), which targets insert slowly on their main thread.
2. **A synthesized ⌘V** (`KeystrokeSynthesizer`, key code from `KeyboardLayoutKeyCode`), only if
   `CGPreflightPostEventAccess()` or Accessibility trust allows it and the captured target is still frontmost
   (`PasteCoordinator.keystrokeTier`).
3. **A toast**, "Press ⌘V to paste". The payload is already on the pasteboard.

**The wait ends when the system says the target has the keyboard.** `KeyboardFocusProbing` (`SystemKeyboardFocusProbe`)
asks Accessibility for the focused application; `FocusRestoration.waitForKeyboardFocus` polls it every 5 ms and returns
once it is the target. 500 ms (200 ms on the activation-notification path) are ceilings, not delays; without
Accessibility the probe answers nil and the ceiling is waited out. An app that reports the keyboard early gets a per-app
settle, never a longer wait for everyone. The shelf hides in `PanelMotion.hideDuration` (0.12 s) because a paste waits
for it.

**Clicks.** `ShelfTap.route` (`Core/Paste/ShelfActions.swift`) decides: a click only focuses a card; a double click
pastes; ⌘-click and ⇧-click select; with a selection a click toggles membership and a double click is ignored. VoiceOver
gets one step (`ShelfClick.activate`). The quick menu keeps one-click paste, and the floating window pastes (or copies)
in place on one click. Keys act on the keyboard-focused card, never the hovered one; hover counts only after the pointer
moves more than 4 pt.

**Delete and actions.** Delete removes the whole selection, or the focused card when none is selected
(`ShelfDeletion.targets`), and asks inside the shelf (`ShelfDeleteConfirmation`): Return deletes, Esc keeps, and while
the question is up no other key reaches the grid. ⌘K opens the focused card's context menu, also while searching, never
while the history is locked; the focused card reports an anchor (`FocusedCardAnchor`) and a right-click is posted at its
center, so the menu stays one definition. The key is mapped in `Sources/Core/Runtime/ShelfCommand.swift`. Esc goes back
one step: a prompt, Quick Look, the hover card, the selection, then the shelf.

**Selection actions.** With two or more selected text or code clips, **Paste All** (⌘P) pastes them at once joined by a
blank line (`ClipJoin.join`; it creates no clip). **Paste One by One** (⇧⌘P) pastes the first clip when the shelf
closes, readies the next through `OwnWriteGate`, and pastes it on the person's next plain ⌘V in any app
(`StackKeyPolicy.isUserPaste`: no other modifier, not Pesto's own). That needs a global key monitor
(`StackPasteSession`), started only with Accessibility and `LaunchMode.current.usesSystemIntegrations`. Without
Accessibility, the key bound to Open the shelf (⇧⌘V by default) puts the next clip on the clipboard. The next clip is
readied 300 ms after a paste. A progress panel ("Pasting 2/5") has Cancel; the status menu offers "Stop Pasting One by
One"; opening the shelf ends a watched run. The double ⌘C Append keeps its own name.

**The hover card** is `HoverCardPanel`, one borderless, non-activating child `NSPanel` of the shelf or floating window
that never becomes key (`HoverCardHost` serves the whole app; a new card replaces the old). It sits above the clip on a
bottom shelf and away from the shelf on a Top shelf and above clips in the floating window
(`ShelfPosition.hoverCardOpensAbove`), centered, clamped to the screen, 8 pt gap, no arrow. It is card material, not
glass, solid under Reduce Transparency, and does not animate under Reduce Motion. It takes the pointer only when its
body scrolls (text and code past 180 pt) and then stays open while the pointer crosses to it
(`DetailPopoverPolicy.grace`, 450 ms); otherwise it is click-through. It has no buttons: actions live in the context
menu and ⌘K, and a long clip is read in Quick Look. A keyboard reveal lasts until focus moves, a key is typed or a
scroll starts, with a 30-second timeout. It shows the body, then one footer line of `DetailFact`s (Core, tested).
VoiceOver gets the facts from the focused card (`voiceOverContent`), since focus never enters the panel.

## Consequences
- Key press to clip is about 180 ms for text and most kinds; `make bench-latency paste` guards it (a dropped ⌘V shows as
  a row with no arrival).
- Every paste runs through `PasteTaskTracker`, so sleep, wake and lock cancel it. A pasted secret leaves the pasteboard
  after `secretClearDelay` (30 seconds) unless something else was copied; a Paste One by One that waits longer finds it
  cleared.
- A covered or hidden card gets no hover card, Quick Look or drag (`CardConcealment`, ADR 0003); a new way to show a
  clip's content goes through it.
- Tests: `PasteCoordinatorTests`, `FocusRestorationTests`, `ShelfActionsTests`, `StackKeyPolicyTests`,
  `DetailPopoverPolicyTests`, `DetailPopoverContentTests`, `DetailFactsTextTests`; UI tests `StackPasteTests`,
  `DeleteConfirmationTests`, `KeyboardNavigationTests`, `CardDetailPopoverTests` double-click to paste. Reduce Motion,
  Reduce Transparency, Increase Contrast, VoiceOver and a second display are checked by hand.

## Docs affected
`docs/guide/using-pesto.md`, `docs/guide/shortcuts.md`, `docs/copy-guide.md`, `docs/feature-reference.md`,
`docs/testing.md`.
