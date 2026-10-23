# 0003. Secrets are masked and pasted without showing, one authentication window guards Show, and a cover hides the shelf while sharing

Status: Accepted

## Context
People copy card numbers, API keys, tokens and passwords from apps that are not password managers, and the shelf is a
row
of cards anyone near the screen can read. Refusing to store such a copy would break the tool: the person copied it to
paste
it again. The goal is a secret that is not readable on the shelf, pasting that stays fast, and no side door (hover,
Quick
Look, drag, AI) that shows what the mask hides.

Pesto asks for Touch ID or the account password in several places. A system dialog took focus from the shelf and closed
it;
the lock's idle timeout and the "recently authenticated" window read as one idea but were two settings. Some Macs cannot
authenticate at all. And a screen share can expose the shelf, while macOS has no public "this screen is captured" signal
and
`NSWindow.sharingType = .none` stopped working against ScreenCaptureKit on macOS 15.4.

## Decision
**Detection and masking.** `SensitiveContentDetector` runs at ingest on a clip's text and on text found in pictures.
Categories (`SensitivityCategory`): `credit_card` (digit groups plus Luhn), `ssn`, `jwt`, `api_key`, `oauth_token`,
`private_key`, `password` and `credential` (a kept password-manager copy, ADR 0004); the first match wins, most specific
first. A hit stores the category and `sensitivityMaskedPreview`; the real text stays in the sealed blob (ADR 0002). The
grid draws the masked preview, and a lint rule keeps `Features/Grid` from reading `previewText`. A pass never sees more
than
`maxWindowBytes` (50,000); larger text is scanned in windows of whole lines (a longer line is cut into 10,000-character
pieces) up to `maxScannedBytes`, which is `ClipSizePolicy.maxTextBytes` (10 MB), so no accepted copy has an unscanned
tail.
A pattern straddling a window boundary can still be missed. A picture, or text over 100 KB, is saved first, judged
afterwards (ADR 0006), and covered until then.

**Covered cards offer no side door.** `CardConcealment` is covered for a masked secret not shown, a clip blurred by the
content filter, a clip awaiting analysis, or a screen-share cover, and then switches off the hover card, Quick Look, AI
actions and drag. New ways of showing or handing out a clip go through it.

**Paste never shows.** Return, ⌘1 to ⌘9 and a click paste a covered card like any card and write the real text. Showing
is
a separate act: the eye button, **Show** in the menu, ⌘Return, or the VoiceOver action Show. Quick Look is not offered
on a
hidden clip, so Show is the one way in.

**Show.** It asks for authentication, then shows the first 500 characters in place. It stays until **Hide**, the shelf
or
floating window closing, the card leaving the screen, the history locking, or the contents becoming covered. The shelf
tells its cards through one counter (`hideSecretsGeneration`). There is no timer. A card blurred by the content filter
(pictures and links, not secrets) is shown without authentication.

**One authentication window** (`AuthenticationGrace`). A success is good for 1, 5, 15 or 60 minutes (default 5; Settings
→
Privacy, "Ask for Touch ID again after"); the same value is the History Lock's idle timeout. It is held in memory, and
the
history locking or the Mac or screen sleeping or waking clears it. Within it nothing asks again.
- Ask unless the window is open: the History Lock unlock, Show, and Allow for a built-in excluded app (ADR 0004).
- `ProtectedAction` (backup, restore, export, import) asks only while the History Lock is on.
- Always ask (`requireFresh`): turning the History Lock off, showing the recovery key (ADR 0010), Clear Everything.
- The prompt is drawn inside the shelf (`AppState.authenticateInShelf`, `ShelfAuthenticationRequest`,
  `BiometricLockOverlay`) with the embedded `LAAuthenticationView`, so the shelf stays open. Use Password falls back to
the
  system dialog, which can pull focus. Without a shelf or Touch ID the system authenticator is used.

**A Mac that cannot authenticate** (`AuthenticationAvailability`, `HistoryLockPolicy`). Anything that asks first fails
closed: Show, Show Recovery Key and Allow are refused and their controls disabled with a reason. Pasting a hidden clip
still
works. The History Lock cannot be switched on, and an existing one can be switched off without asking. Clear Everything
keeps its confirmation and is not refused. Features that need something absent get one rule: never possible on this Mac
(hidden, with one plain line in Settings), fixable by the person (shown disabled, with the reason and a button to the
pane),
or turned off in Pesto (disabled, "Turned off in Settings").

**Screen-share cover**, with no Screen Recording permission and no private API. `ScreenShareDetector` is
heuristic and permission-free. While `Setting.screenSharingPrivacy` is on (off by default; Settings → Privacy) it checks
every 3 seconds for a mirrored display, a running sharing or recording app (lowercased bundle IDs: Screen Sharing, Zoom,
Teams, Webex, Loom, OBS, FaceTime, Discord), or `BrowserShareSignature`: an on-screen window 30 to 120 pt high and 200
to
1000 pt wide, at the status-window layer owned by a Chromium browser or at the floating-window layer owned by Firefox,
read from `CGWindowListCopyWindowInfo` (owner, layer, bounds; never titles). A single-window share draws the same bar as
a
full-screen share, so either covers, on purpose. **Hide Clip Contents** covers by hand: a status-menu item, the
`SetClipContentsHiddenIntent` Shortcuts action, a Focus filter (`HideClipContentsFocusFilter`) and the optional
`GlobalShortcut.toggleClipContents`. `ContentCover.isCovered(manual:settingOn:shareDetected:)` is the one rule; a
hand-hide
works with the setting off and is not saved.

## Consequences
- False positives happen (a long identifier can look like an API key); the cost is a masked card that still pastes.
- Detection is local; no clip text is sent anywhere (ADR 0005).
- An unattended unlocked Mac can show hidden clips inside the window; 1 minute is the shortest choice.
- A share of one Chrome tab, a dismissed bar and Safari are not seen; Settings says so and points to Hide Clip Contents.
- Pasting a secret keeps it off Universal Clipboard and concealed (`AppState.beginWrite`).
- Tests: `SensitiveContentDetectorTests`, `CardConcealmentTests`, `HiddenClipRevealTests`, `HiddenClipRevealUITests`,
  `AuthenticationGraceTests`, `AuthenticationAvailabilityTests`, `ShelfAuthenticationTests`, `HistoryLockTests`,
  `AuthenticationUnavailableUITests`, `ContentCoverTests`, `BrowserShareSignatureTests`, `ScreenShareDetectorTests`.
  Touch ID in the shelf is on the manual checklist.

## Docs affected
`AGENTS.md` (invariant 4, the covered-card pitfall), `docs/guide/privacy-and-security.md`, `docs/guide/settings.md`,
`Sources/Features/Overlay/CLAUDE.md`.
