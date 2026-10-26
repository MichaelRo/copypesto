# Testing and verification

`scripts/verify.sh` is the gate. Run it before claiming any task done and paste its summary.

```bash
scripts/verify.sh          # lint, Core tests, Debug build, hosted + UI tests, screenshots (about 40 minutes)
scripts/verify.sh --fast   # lint, Core tests, Debug build only (a few minutes on a cold build)
make verify                # same as scripts/verify.sh
make verify-fast           # same as scripts/verify.sh --fast
```

It prints one line per step and exits non-zero on any failure. The full gate also builds the Release configuration
(`release build (hardened runtime)`), checks the memory budget on the 5,000-clip history and with 300 large pictures, and
judges the snapshots; `--fast` stops after the Debug build:

```
=== verify summary (an example; the counts below change with every test added) ===
PASS  lint                                 Found 0 violations, 0 serious in 216 files.
PASS  core tests                           785 Swift Testing + 38 XCTest, 0 skipped (runs: 44+785)
PASS  build (Debug, warnings as errors)
PASS  release build (hardened runtime)
PASS  memory budget
PASS  memory budget, pictures
PASS  hosted + UI tests                    passed=430 failed=0 expected=0 skipped=0; hosted=294 ui=136 skipped=0
screenshots: .build/ui-screenshots/20260924-185508 (19 PNGs)
RESULT: PASS
```

A green summary has to mean the tests ran. `scripts/verify_judge.py` fails the gate when fewer tests ran than its floors
(Core 950 Swift Testing and 30 XCTest, hosted 270, UI 130, snapshots 30) or when a test was skipped that
`scripts/verify-allowed-skips.txt` does not name (a Mac without the on-device model, memory deltas on CI). The script
refuses to start while Pesto is running (a running copy answers for the tests' windows), holds the Mac awake with
`caffeinate -dis`, and takes the Core totals from every "Test run with" line, because Swift Testing prints one per run.

### Running the gate cheaply

The gate already keeps its output small: each step writes its log to a file, and the terminal gets one progress line per
step and the summary. Reading the logs is what costs time and tokens, so don't.

- Start it in the background (the shell tool's `run_in_background` option) and wait for it to finish rather than
  polling. It takes about 40 minutes with the UI tests.
- Read only the summary: `.build/verify/<run>/SUMMARY.txt`, or the last 15 lines of the output.
- On a failure, read `.build/verify/<run>/failures.txt`: one line per failing test (`target/Suite/test: message`),
  from the result bundle. Open a log only for a failure whose line does not explain it.
- The first UI run after an unlock often fails with "Timed out while enabling automation mode". Re-run just the failed
  tests with `scripts/verify-rerun-failed.sh` (Pesto quit, as for the gate). It prints the same kind of summary and
  says it is a partial run: only a full `scripts/verify.sh` counts as the gate.
- A test that fails only because the test host died ("Test crashed with signal …") is re-run once, alone; if every failure of the run was such a crash and each passes on its own, the gate passes and its summary names them, and `concurrent.log` in the run folder lists the build and test processes sampled every 5 s so the cause can be matched (do not run `make bench-latency` or another build during the gate). An assertion failure or a second crash fails the gate.
- A hosted Swift Testing suite nested in `HostedGlobals` is selected by function, `-only-testing:'PestoTests/HostedGlobals/<Suite>/<test>()'`; the suite name alone matches nothing and the run still says `TEST SUCCEEDED`. Read the `Test run with N tests` line for the count that ran.
- `scripts/verify.sh --fast` (lint, Core tests, Debug build) is enough between commits; the pre-commit hook already
  runs lint and the Core tests.

Logs are in `.build/verify/<run>/`. Screenshots are in `.build/ui-screenshots/<run>/<Test>/<step>.png`; a failing
step also leaves `<step>.txt` (the accessibility tree) next to them.

## Latency and memory on a real target app (`make bench-latency`)

`make bench-latency [paste|copy|open|hover|memory|both|all] [runs]` builds a signed Profile copy of Pesto, runs it in UI-test mode with
an isolated history and `PESTO_UITEST_REAL_PASTE=1`, and drives it with `scripts/bench-latency/BenchTarget.swift`, a small
app that is the paste destination (it logs when text arrives), presses ⌘1 to ⌘8, and writes clips to the **real clipboard**
for the copy runs. It saves the clipboard first and puts it back, even on Ctrl-C. Pesto writes its stage timings to
`perf-timeline.tsv` on the system uptime clock and `analyze.py` joins them with the driver's rows, prints a table per kind
and exits non-zero over budget. Needs Pesto quit, the Mac unlocked and left alone for about 15 minutes (all scenarios),
and Accessibility for the app that runs it (it posts key events). It is not part of `verify.sh`.

## One-time machine setup (needs `sudo`)

Only the maintainers' gate needs this. If you are sending a pull request, `make lint` and `make test-core` are enough; the
UI tests change system security settings (automation mode, developer tools), so run them only on a Mac you are willing to
change, or in a virtual machine.

UI tests drive real windows, so macOS must allow it:

```bash
sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch
sudo DevToolsSecurity -enable
sudo automationmodetool enable-automationmode-without-authentication
```

The first UI run may show a system dialog asking to allow UI automation; approve it.

## What each layer tests

| Layer | Command | Runs | Touches |
|---|---|---|---|
| Core (`PestoCoreTests`, `PestoRegressionTests`) | `swift test` / `make test-core` | SPM, no app | Nothing outside the process; a test that needs a Keychain item deletes it |
| Hosted (`PestoTests`) | part of `verify.sh` | Inside Pesto.app as the XCTest host | Nothing real: `LaunchMode.hostedTests` skips boot, and defaults, pasteboard, storage path and key are isolated; no link preview or other network request (`LinkPreviewPolicy` is off outside a normal launch) |
| UI (`PestoUITests`) | part of `verify.sh` | Pesto launched with `-UITestMode` | Nothing real (below); link previews are off, so seeded URL clips make no request |
| Snapshot (`PestoSnapshotTests`) | `make test-snapshots` | Inside Pesto.app | Run by `verify.sh` only on the macOS that drew the baselines (`Tests/PestoSnapshotTests/baseline-macos`) and never on a hosted CI runner (its virtual display draws the pictures differently), and the summary says "snapshots skipped: …" otherwise; when to record them: "Card snapshots" below |

## Card snapshots: when they are taken

A baseline in `Tests/PestoSnapshotTests/__Snapshots__` is a picture of what a card, chip or hover card should look like
on the macOS version that drew it. It is a record of a decision, so it changes only when a person decides the picture
should change. The gate never records one (a regression would become its own baseline).

| Trigger | What to do |
|---|---|
| A change that deliberately alters how a card, chip or hover card looks (for example `docs/design/card-typography.md`) | In the same pull request: delete the affected PNGs, run `make test-snapshots` (a missing file is recorded, a different one fails), look at each new picture, commit them. The reviewer reads the pictures in the diff before the code |
| The development Mac moves to a new macOS major version | A pull request of its own, "chore(snapshots): re-record on macOS NN", with the pictures reviewed one by one; no code in it |
| A snapshot fails and nobody meant to change the card | A bug. Fix the card, never the picture |
| Anything else | Do not record |

The gate runs the snapshots on the Mac that recorded them (audit P-44): `scripts/snapshot-os.sh` compares the macOS major
version in `Tests/PestoSnapshotTests/baseline-macos` with this Mac's, `verify.sh` runs `PestoSnapshotTests` and judges at
least 30 passing ones when they match, and the summary line says "snapshots skipped: baselines are macOS NN, this Mac is
macOS MM" when they do not. `make test-snapshots` refuses on a different macOS too. CI skips them, because its runners
are another macOS version. Moving to a new macOS major version is the "chore(snapshots)" pull request in the table above:
re-record with `PESTO_SNAPSHOT_OS_OVERRIDE=1 make test-snapshots` and change `baseline-macos` in the same pull request (the
two must agree, and `SnapshotBaselineTests` checks the script and the file).

## `-UITestMode`

A UI-test launch runs the real UI on isolated data. `RuntimeConfiguration` (Core) reads the launch environment:

| Variable | Meaning |
|---|---|
| `PESTO_UITEST_SESSION` | Names the pasteboard and command queue; the private defaults file lives in `PESTO_UITEST_DIR`, so it goes when the test's directory does |
| `PESTO_UITEST_DIR` | Working directory shared by the app and the runner (store, paste log, commands, ready marker) |
| `PESTO_UITEST_SEED` | `empty`, `basic` (14 items: text, code, URL, color, images, two masked secrets) or `large` (5,000) |
| `PESTO_UITEST_ACCESSIBILITY` | `trusted` or `denied`: the stubbed Accessibility state |
| `PESTO_UITEST_IMPORT_FIXTURE` `otherfile` | Other File… reads a built-in CSV instead of opening a file panel |
| `PESTO_UITEST_AI_FIXTURE` | `1` swaps the on-device model for a fake that answers at once (budget 300 characters) and reports AI as available, so `AIPartsUITests` drives the panel on any Mac |
| `PESTO_UITEST_KEYLOSS` | `1` forces the "can't unlock your history" flow: the alert comes just after launch, and the restore window uses a fixture backup (`KeyLossFixture`: passphrase "fixture passphrase", one clip) instead of a file panel; use the empty seed |
| `PESTO_UITEST_REAL_PASTE` | `1` uses the real pasteboard and a real paste instead of the private pasteboard and the paste log (`make bench-latency`) |
| `PESTO_UITEST_PERF_TIMELINE` | `1` makes Pesto write its stage timings to `perf-timeline.tsv` (`make bench-latency`) |
| `PESTO_UITEST_REAL_DEVICE` | `1` shows the real Touch ID view and the on-device model (`make capture-real`) |
| `PESTO_UITEST_BACKDROP` | A backdrop style drawn behind the shelf for marketing pictures (`make marketing-images`, and the frames of the website's scenes and the launch videos, `make marketing-loops`) |
| `PESTO_UITEST_DEFAULT_<key>` | Preference overrides, typed (`true`, `5`, `dark`): e.g. `appearanceMode`, `hasOnboarded` |

What is isolated or stubbed under test, and the single seam for each (a lint rule keeps the real API from coming back):

| Real thing | Seam | Under test |
|---|---|---|
| `UserDefaults.standard`, `@AppStorage` | `AppDefaults.store`, `SafeHostingView(pesto:)` | Private suite in a session folder of the temporary directory (the work directory in a UI run), never `~/Library/Preferences` |
| `NSPasteboard.general` | `AppPasteboard.general` | Private named pasteboard; a test simulates a copy by writing to it |
| `~/Library/Application Support/net.copypesto.pesto` | `AppPaths.supportDirectory` | The working directory (a `pesto-` folder in the temporary directory when none is given) |
| Keychain encryption key, device id | `BlobEncryption`, `StorageService` | Per-session in-memory key and id |
| `AXIsProcessTrusted`, the permission prompt | `AccessibilityAccess` | Stubbed state; never prompts |
| Focus restore + AX write + ⌘V | `PasteCoordinator` + `PasteRecorder` | Appends what would be pasted to `paste-log.jsonl` |
| Global hotkeys, Sparkle, global ⌘C monitor, screen-share detector | `LaunchMode.usesSystemIntegrations` | Not started |
| The hotkeys' effect | `UITestCommand` via `UITestCommandQueue` | Files in `commands/` that the app polls every 100 ms |

The runner is sandboxed and cannot post distributed notifications, which is why commands travel as files. The app writes
`ready.json` once seeding is done, and logs each command it receives to `commands.log`.

The test app runs as a regular app (Dock icon, a second menu-bar item) so XCUITest can drive it. It registers no hotkeys,
so it does not collide with a Pesto you are running.

## Writing a UI test

Subclass `PestoUITestCase` (`Tests/PestoUITests/PestoUITestCase.swift`):

```swift
final class MyFlowTests: PestoUITestCase {
    func test_whenSomething_thenSomething() {
        launch(seed: "basic")            // waits for the ready marker
        showOverlay()                    // sends UITestCommand.showOverlay
        card(containing: "Quarterly").click()
        XCTAssertEqual(waitForPaste(count: 1), ["Quarterly report draft — final review pending."])
        capture("after-select")          // PNG of the overlay, not the full screen
    }
}
```

Identifiers live in `Sources/Shared/Components/AccessibilityID.swift` (compiled into both the app and the tests).
An `NSPanel` is not exposed as a window, so panel roots carry an identifier and are found with `element(_:)`. After
adding a test file run `make generate`.

A known bug is recorded with `XCTExpectFailure` (see `OverlayFlowTests`), never by deleting or skipping the test.

## Privacy and housekeeping

- Captures are scoped to the app's own overlay or window. The overlay is translucent glass, so a capture of it includes
  whatever is behind that strip of your desktop.
- Xcode attaches a **full-screen recording** of each UI run to the result bundle (`.build/verify/<run>/tests.xcresult`).
  `verify.sh` does not copy it into the screenshot folder. Delete `.build/verify` when you are done with a run.
- After a UI run macOS protects the launched runner app from being overwritten, so `verify.sh` moves the previous one
  to `.build/stale-runners/` before building. That folder is safe to delete.

## Troubleshooting

| Symptom | Cause |
|---|---|
| "The test runner hung before establishing connection" | Setup above not done, or Xcode's first-launch components are missing |
| "Test crashed with signal kill before establishing connection" | Runner built unsigned; use `verify.sh` (ad-hoc signing) |
| `ld: open() failed, errno=1` on the runner | Stale runner bundle; move `.build/xcode/Build/Products/Debug/PestoUITests-Runner.app` aside |
| Overlay "did not appear" | Read `overlay-missing-commands.txt` (did the app receive the command?) and the tree next to it |
| A trace or screenshot is empty or black | The screen is locked or asleep: nothing is drawn. Unlock it first |
| `PESTO_UITEST_DIR` is ignored (no `ready.json`) | The directory name must start with `pesto-` (`RuntimeConfiguration.temporaryDirectory`) |
| A coordinate click or drag does nothing | Raw screen events go to the topmost window, which may be another app; element clicks do not. Test the stored value, not the drag |
| A SwiftUI `.alert` is not found in `app.alerts` | It is `app.sheets` or `app.dialogs` |
| The key-loss tests fail with query timeouts or an alert that never returns | A Keychain access prompt left by an earlier run, or a macOS permission dialog (screen recording after a screenshot), is on screen. Clear it (restart `SecurityAgent` for a stale Keychain prompt) and re-run; the tests passed five times in a row once both were gone (2026-10-23) |
| `UserAuthenticator` refuses in a test | The stub grants only when `uitestAuthenticationGranted` is `true` in the launch defaults |
| An accessibility-audit test fails on every window with "Element has no description" (or on contrast) at a position outside the app | Something else on screen covers or sits over the test windows (a notification banner, another app's window). The same suite passes when re-run alone with the screen clear; seen three times |

## Rules for new work

1. A bug fix starts with a failing test. Tests that read a real system resource (Keychain, defaults, pasteboard, store)
   go through the runtime seams and use a unique name per test.
2. Mutation-check a new test once: break the code it claims to guard and see it fail.
3. UI tests assert on the real app's accessibility tree and measured frames, not on screenshots.
4. Performance budgets assert on a developer Mac and only measure on CI.
5. A claim that something is *not* read or *not* done needs a fake that counts the reads (`FakePasteboard.contentReads`).
6. `-only-testing` on a suite nested in `HostedGlobals` must name the function, `PestoTests/HostedGlobals/<Suite>/<test>()`;
   check the "Test run with N tests" line, because a selector that matches nothing still reports success with 0 tests.
7. A layout change that shows more of a screen widens what `AccessibilityAuditTests` judges: run it after one.
8. Tests that share a temporary directory must not delete it for each other; give each test its own folder.

## Pictures only a real Mac can take

The lock screen picture (`docs/images/history-locked.png`) and the Ask picture (`ask-pesto.png`) come from the stubbed run
unless you retake them: the stub shows a plain button instead of the system's Touch ID view, and Ask falls back to its
rules instead of Apple's on-device model. On a Mac with Touch ID and Apple Intelligence, with nothing else on screen,
run `make capture-real`. It runs `RealDeviceCaptureTests` (skipped everywhere else), which launch the app with
`PESTO_UITEST_REAL_DEVICE=1` (honoured in UI-test mode only), then copies the two pictures into `docs/images`. Look at
both before you commit them: nothing but Pesto may be in them.

## Before a release: what a person has to check

The runner has no real Accessibility grant, no other apps to paste into, no Touch ID and no way to press the system
hotkey. Run this one checklist by hand on a `make install` build, except where a line says it needs the DMG. Each check
ends with **Pass:**, what a pass looks like. Nothing may be on screen from the system first: a leftover Keychain access
prompt or a macOS permission dialog (screen recording after a screenshot) makes the key-loss UI tests time out; restart
`SecurityAgent` to clear a stale Keychain prompt.

**Install, signing and updates (1.0 is unsigned, `docs/release.md`)**
- Unsigned install from the DMG: download `Pesto-<version>.dmg` from the release, open it, drag Pesto to Applications and
  open it. macOS says it could not verify Pesto; Done, then System Settings → Privacy & Security → Open Anyway.
  Pass: Pesto opens after Open Anyway and the setup window shows.
- SHA-256: `shasum -a 256 ~/Downloads/Pesto-<version>.dmg` and `codesign -dv --verbose=2 /Applications/Pesto.app`.
  Pass: the hash equals the one in the release body, the `.sha256` file and the download page, and `codesign` names the
  "Pesto Release" identity with no Developer ID team.
- Local update test (`docs/release.md`, "Each release, unsigned (1.0)"): install 1.0.0, serve a throwaway 1.0.1 from a
  local appcast, choose Check for Updates… from the menu bar. Pass: it updates to 1.0.1, the history opens with no
  Keychain prompt, and paste still works without granting Accessibility again.
- Fresh install: the Accessibility prompt appears, and granting it moves onboarding forward. Pass: the setup window
  advances to the next step as soon as the grant is on.
- Launch at login survives a reboot. Pass: after a restart Pesto is in the menu bar without being opened.
- Missing key: on a scratch user or a VM (it deletes the real key), quit Pesto, delete the blob-key item in Keychain
  Access, relaunch. `KeyLossRecoveryUITests` covers the flow after the alert; by hand check only that a real missing key
  reaches it. Pass: the "can't unlock your clipboard history" alert shows and no new key appears until you pick Start
  With Empty History or Restore from Backup…. Then: a wrong passphrase shows an error and Close brings the alert back with
  the history untouched; a cancelled file picker does the same; a right passphrase shows the preview ("Your current
  history cannot be opened…") and Restore replaces the history and Pesto finishes launching; closing the window with its
  red button also returns to the alert.
- Clipboard access: in System Settings → Privacy & Security → Paste from Other Apps set Pesto to Deny, then to Ask.
  Pass: the status menu shows "Clipboard Access Limited — Open Settings…", Settings → General (Permissions) shows the
  warning, and its button opens the right pane.
- Update notice placement: on a `make run` build (not the DMG), choose Check for Updates…. Pass: the toast "This build
  does not check for updates." appears under the menu bar and the About window says development build.

**Shortcuts and pasting**
- Copy from the shelf (a card's menu, Copy As…, a color format, or a click in the floating window set to copy). Pass: the
  clip moves to the front, as a paste does, and its paste count does not change.
- Copy (⌘C) on the shelf. Pass: it copies the focused clip with no beep and the clip moves to the front; in the search
  field it copies the selected text; with a card menu open it still works.
- Quick Look (⌘Y): copy a GIF from a browser, a page of a PDF and a WebP picture, and two files in Finder. Pass: ⌘Y shows
  the GIF animating, the PDF page and the picture, not text, and the arrow keys step between the two files. The preview
  is no larger than about half the display, Esc closes only the preview (the shelf stays), arrow keys then move between
  clips and open no preview, and ⌘Y opens it again.
- AI result Paste (needs Apple Intelligence): run an action on a text clip and press Return. Pass: the answer lands in
  the app you were in, also after reading it for over 20 seconds; Copy Result files the answer in the history, Paste does
  not, and the clip it was made from moves to the front.
- Long Summarize (needs Apple Intelligence): run Summarize or Key Points on a very long text. Pass: an answer for the
  whole text arrives (the guide says it is read a part at a time) in a panel as tall as the answer, with Close, Paste, Copy Result
  and Done in one style.
- ⌘⇧V from TextEdit, VS Code, Chrome and Slack. Pass: the shelf and the caret quick menu open, and pasting lands in each.
- Paste a text, link, picture and file from the shelf into TextEdit, Safari, Chrome, Slack, Terminal and VS Code (Return
  and double click). Pass: every paste lands; none does nothing.
- Shortcut recorder: record ⌘⇧V while it is already set, record ⌃1, and press Esc while recording. Pass: the shelf does not
  open and the shortcut stays; ⌃1 is refused (pinned slots); Esc cancels.
- ⌃⌥⌘V (paste as plain text): `log show --last 5m --predicate 'category == "hotkey"'`. Pass: it shows "Registered Paste
  as plain text: status 0" and "Pressed …" (a status of -9878 means another app holds the combination).
- Double ⌘C in a real app, and a ⌘V stack across apps. Pass: the double copy appends, and each plain ⌘V pastes the next clip.
- Select a card and immediately sleep the Mac, then wake it. Pass: nothing pastes on return.
- Drag cards into TextEdit, Notes and a Safari address bar (text, code, an image, a URL), and a text clip, a picture clip
  and a three-file clip to the Desktop and a Finder window (N-26). Pass: each arrives as what it is.
- Drag a clip out of the shelf onto an input box that sits behind the glass (the Claude desktop input). Pass: the shelf
  goes invisible and click-through once the pointer leaves the top command bar, and the drop lands in the input.
- Copy a GIF with Copy Image in Chrome, Arc and Edge. Pass: it plays on the card.
- Quick-menu position on a second monitor. Pass: it opens on that monitor and Escape dismisses it while typing in another app.
- Open the shelf from the menu bar item, `open pesto://open`, a Shortcut (Open Pesto) and the Control Center button while
  a text field has the caret (N-02, N-09). Pass: each opens the full shelf and Return pastes into the app that was in front.
- With the shelf's app on a second display (N-23). Pass: the shelf, the manual-paste toast, the Paste One by One panel and
  the floating window appear on that display.
- With the shelf set to Top (*Settings → Appearance*), also with the menu bar set to hide itself, with the Dock on the
  left or right, in a full-screen app and with Stage Manager on. Pass: it hangs below the menu bar (below the notch on a
  notched Mac), the hover card opens below it and grows from its top edge; the stack HUD (top right) and the manual-paste
  toast (bottom center) may overlap the shelf, which is expected (ADR 0013).
- Remote photos (UI tests cannot copy on an iPhone; run `make install` first, an older installed copy keeps files from
  other devices as dead paths): with Other devices on, copy a photo or a PDF on the iPhone, then paste a file clip whose
  file you deleted. Pass: nothing from the phone is kept, "Left out of your history" counts it in Settings → Privacy, ⌘V
  still pastes it in any app, and a toast says nothing was pasted for the deleted file.
- The color panel from the shelf, Paste the previous clip after an iPhone copy, and the Other Devices chip with the
  setting off. Pass: the panel opens, the previous clip pastes, and the chip is hidden.
- The snippet editor in the list: add, edit, Esc, ⌘Return, and a clip's ⌃N keycap on the card and in the hover card.
  Pass: each works, and the keycap shows in both places.
- Shelf suggestions (ADR 0014): paste the same clip 6+ times from the shelf. Pass: after 1.5 s dwell, a bottom banner
  appears ("Set ⌘N as a shortcut for this clip?"), the target card gains a 2 pt accent ring, and a dashed ghost keycap
  appears with a subtle pop settle. "Set shortcut" (or Return) assigns the slot; "Not now" dismisses it; 4 consecutive
  declines turns off the feature; Settings → General toggle and "Reset suggestions" button work; History Lock suppresses
  suggestions without wiping the ledger; Clear History and Restore wipe the ledger.
- App chips and URL card actions: hover across app filter chips. Pass: chips stay steady 24×24 pt circular icons with
  native tooltips and do not jump horizontally; right-click a URL card: "Copy Page Title" and "Copy Preview Image" appear
  directly under "Copy".

**Privacy**
- Touch ID lock and unlock, the password fallback, and one shared timer for protected actions. Pass: the lock asks for
  Touch ID, falls back to the password, and a protected action inside the "Ask for Touch ID again after" window asks nothing.
- Show on a hidden clip with Use Password…. Pass: the shelf stays open while the system dialog is up and the clip shows
  afterwards (a known defect while the Touch ID prompt itself is up, filed as an issue).
- A copy from 1Password or Apple Passwords. Pass: it is not captured.
- A shown secret. Pass: it stays shown until Hide, closing the shelf, a lock or a cover.
- A share from Google Meet in Chrome (whole screen or a single window) with Hide During Screen Share on (Chromium shows
  the floating sharing bar window for both, ADR 0003). Pass: the cards are covered within 3 s.
- Hide Clip Contents from the menu bar, and as a Shortcuts action and Focus filter. Pass: the cards are covered each way.
- Copy `https://example.com` and `file:///Applications/Safari.app`. Pass: the web clip's menu says Open in Browser and
  opens the page; the file URL text clip's menu says Show in Finder and selects the file without launching it; both
  offer the same single action to VoiceOver.
- Lock the history (or let it lock). Pass: nothing can be undone, and after unlocking the stack is empty; Clear History
  and Clear Everything leave nothing to undo.

**Look and feel**
- The menu-bar icon (2026-10-22): with Appearance forced to Dark on a Mac set to Dark whose wallpaper makes the menu bar
  light (or the reverse), then change the wallpaper, switch Spaces and wake the Mac. Pass: the Pesto icon always matches
  the other menu-bar icons; hiding the menu-bar icon works.
- Each theme in light and dark with its icon. Pass: text, accent and the icon read on every one.
- Wallpapers: System Settings → Appearance with the transparency slider at minimum, middle and maximum, Reduce
  Transparency, Increase Contrast and Reduce Motion, over the lightest and darkest wallpaper. Pass: the shelf, Settings
  and the quick menu stay readable, the focus ring is visible (A-14), the card header time in Mortar dark reads (D-07,
  estimated 4.46:1), and the hover card does not scale.
- Text size: set the largest text size and open the shelf, Settings and setup. Pass: no text is cut off or overlaps.
- Import offer with two or more clipboard managers really installed (Paste and Maccy). Pass: the shelf says "You have
  Paste and Maccy", *Choose…* opens Settings → Data scrolled to **Found on this Mac** with each app's own icon, *Import…*
  on a row asks for Touch ID and a file for that app only, and the row then says "Imported N clips".
- Card typography (`docs/design/card-typography.md`, option B): copies from three different apps on every theme in light
  and dark at Small, Medium and Large. Pass: the header names the app at a glance (the 32% wash is enough on Parmesan and
  Pine nut), the text is the loudest thing on the card, and a long text shows 4, 5 and 6 lines with a clear gap above
  the footer. If the app color is lost on a theme, fall back to option A.
- Card whitespace (`docs/design/card-whitespace.md`): copy a web page's text with blank lines above it, a text with a
  U+2028 line break and a text of 501 characters. Pass: the card starts at the first word, shows the paragraphs with a
  slim dotted gap, the 501-character clip says "501 characters" only, a short three-line clip says "N characters · 3
  lines", and the cards on the welcome screen and in Settings → Appearance are the same.
- Hover card: scroll a long clip with the pointer inside the card, then leave it. Pass: it closes after about half a
  second and does not flicker between neighboring clips, also in the floating window and on a second display.
- The 2026-10 review changes: run Describe Image or Summarize; delete a clip; in search, Tab to a filter chip; look at
  the locked shelf's chip row. Pass: the answer panel is as tall as its answer with a readable source quote in light and
  dark, the Undo banner sits above the clips' headers without covering them, the chip's focus ring is whole at the
  bottom, and the locked shelf shows no readable chip or card text.
- Collection chips (2026-10-23; XCUITest cannot drive a drag session, so this is by hand only): drag a chip along the
  row, use Move Left and Move Right in a chip's menu, and drag a clip onto a chip. Pass: the cursor never shows the
  not-allowed sign, the dragged chip leaves a dashed empty slot, the other collection chips slide to the new order without
  jitter, the tag and app chips fade, dropping keeps the order, moving out of the row puts it back, Move Left/Right do the
  same, and the clip dragged onto a chip gets the ring and moves into it (a known visual-treatment defect is filed as an issue).
- Onboarding card strip (2026-10-23): scroll it by hand with a trackpad and let go. Pass: it rests about a second, then
  drifts on from where it stopped with no jump (a short ease-in), and stays still with the pointer resting on it (a known
  drift defect is filed as an issue).

**Accessibility**
- VoiceOver in Settings (Tab into the pane first; arriving from the search field lands on the window, not the controls).
  Pass: Space on a pop-up ("Keep clips for") opens it and Return picks a value; Space on a shortcut's "Options for …"
  button opens its menu (Change…, Reset to Default, Turn Off); Space on "Allow…" and "Add App…" in Privacy opens theirs;
  each theme, icon and swatch tile is announced with its name and "selected"; the two menu buttons and the Privacy
  disclosure ("What stays readable") work (not checked by hand since `PopUpMenuButton` replaced SwiftUI's `Menu`).
- The hover card and VoiceOver: VoiceOver never enters the panel (it never becomes key). Focus a clip. Pass: VoiceOver
  speaks its facts (app, time, size) from the card itself, and the toast "Press ⌘V to paste" is announced once when
  auto-paste is off.
- VoiceOver on a focused clip with the More Content rotor ("Details", "Text"), and on the shelf. Pass: the rotor lists
  both and speaks the clip's text and facts (card actions are a known gap, A-07, filed as an issue).
- The lost-key restore window with VoiceOver and the Accessibility Inspector. Pass: VO+Right reaches the warning "Your
  current history cannot be opened on this Mac. Restoring replaces it with this backup." and the Restore and Cancel buttons.
- Full Keyboard Access and the beeps (A-05): ⌘S on a clip that is not a picture, ⌘0, ⌃ with a letter and Page Up in the
  search field, ⌘W and ⌘H. Pass: none beeps, ⌘W closes the shelf, ⌘H does nothing, and ⌘Q still quits.
- Keys on the shelf (`docs/guide/shortcuts.md`): ⇧Return in search, and ⌥→, Page Down, ⌥← and Page Up with 30 or more
  clips. Pass: ⇧Return pastes the focused result as plain text, and the others move a screenful (the visible clips less one).

**Data and performance**
- Restore a backup with a shorter retention in it. Pass: *Apply These Too* appears in the done step.
- Footprint after days of real use: `footprint <pid>` (peak as well as current), and `ps eww <pid> | tr ' ' '\n' | grep
  Malloc` on a launch from Finder. Pass: steady state under 150 MB.
- `make bench-latency open 7` three times (the only check that has the retention pruner, a 5,000-clip history and a copy
  made while the shelf was closed; `OverlayPerformanceTests` has none of them). Pass: the median is under 100 ms each time.
- `make bench-scroll`. Pass: it prints `shelf scroll travel` of at least 300 points for both histories (a run in which
  the shelf did not move fails) and stays within the scroll budget.
- `make bench-latency all 7`, and `make bench-undo` after a change to Undo. Pass: both stay within budget.
- A store fixture from the shipped build is added before each release. Pass: the fixture opens in the next build.

**Undo** (ADR 0008; `make bench-undo` for the numbers)
- Delete one clip, then several with Space and ⌫, then a collection from its chip, with the shelf at the bottom and at the
  top. Pass: each shows the bar with Undo, ⌘Z brings it back in the same place with its pin, note and shortcut, and ⇧⌘Z
  deletes it again.
- The delete question. Pass: it says "You can undo this with ⌘Z" for an ordinary clip (including secrets and credit cards,
  which are sealed in memory under ADR 0008) and "This can't be undone" for a password manager copy, a burn-after-paste or
  expiring clip and a very large one (> 4 MB).
- Rename, add a note, a tag, move a clip to a collection by dragging it to a chip, reorder cards in a collection, pin,
  give a shortcut; create, rename, duplicate and reorder collections. Pass: ⌘Z undoes each, in the order made.
- In Settings → Snippets add, edit and delete a snippet and import a snippets file; in Settings → Collections import a
  collection file. Pass: the Edit menu's Undo names each and undoes it, and a text field being edited keeps its own ⌘Z.
- ⌘Z in the shelf's search field. Pass: it undoes typing while there is text, and the shelf's last action when the field
  is empty.

## Lessons from the test suite

- **A longer line of text in the setup window can fail the accessibility audit on a label you did not touch** (2026-10-16): the audit samples pixels at each element's frame, and a callout that wrapped to two lines moved the encryption-key label to a position it flagged, as a two-line toggle caption did on the last step. After any copy change in `OnboardingView`, run `test_onboarding_passesTheAccessibilityAudit` and `test_onboardingLastStep_passesTheAccessibilityAudit`.

- **Audits judge what is in front.** A launched Pesto can sit behind the app the run started from, so an audit once measured another app's pixels. Every audit runs once per appearance (`auditInBothAppearances`) and calls `app.activate()` first; `PestoUITestCase.capture` photographs the screen under the window, so activate before it, and read the pictures from a `-resultBundlePath` bundle with `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>` (needs `DEVELOPER_DIR` set to Xcode).
- **The audit's panel list is explicit.** The floating window and the quick menu are panels that `app.windows` does not list, so "inside Pesto" comes from the windows plus the three panel identifiers. `KnownAuditFinding` matches type, description, element type, identifier and label with a ceiling on how many may appear; lowering a ceiling by one makes the run fail, which proves the check.
- **A hand-run UI test with signing off fails with "PestoUITests-Runner is damaged".** Use the flags in `scripts/verify-rerun-failed.sh` (`-derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`).
- **Check the executed-test count of a narrow run.** A wrong `-only-testing` name runs zero tests and reports success. Swift Testing takes the suite name (`PestoTests/AutoBackupServiceTests`); a suite nested in `HostedGlobals` needs the function, `PestoTests/HostedGlobals/<Suite>/<test>()`. A new test file is invisible to `xcodebuild` until `make generate`.
- **State set in `.task` is not on the first frame**, so a screenshot taken straight away misses it; set it in `init`.
- **Look at the screenshots after a layout change**, not only at the assertions: a pane header with `.fixedSize` shifted the whole Settings window 48 pt up and nothing failed. Four visible defects once passed every test and showed only in the gate's pictures.
- **A test that lists a shared directory races every parallel test.** Give it a private directory (`PasteLibraryReader` takes a `FileManager` for this).
- **A test that touches the Keychain writes one real item under a unique service and deletes it.**
- **Swift Testing: a mutating call cannot sit inside `#expect`.**
- **"Timed out while enabling automation mode" is a macOS stall**, not a test failure; a re-run clears it. If `automationmodetool` says the device requires user authentication, repeat the one-time setup above after an OS update.
- **Fixtures come from the real world.** A bench that presses ⌘N for the Nth card must track the shelf's order (a paste moves the clip to the front); a target app needs an Edit menu or ⌘V does nothing; posting ⌘ through flags on the digit's events can leave ⌘ held in the system, so send ⌘ down and up.
- **Measure the path the user takes** (copy, then open; key press, then text in the app) with a real target app and `make bench-latency`, not one stage on its own: the search budget test measured the preview alone at 19 ms while the shelf took 79.
- **A recompile can surface old warnings.** The gate counts warnings as failures, and an incremental build had hidden three for weeks.

## Test hooks, warnings and entitlements

- **Test hooks are an `Info.plist` property.** `PestoAllowsTestHooks` is `$(PESTO_ALLOWS_TEST_HOOKS)`, set in `Pesto.yml`: `NO` in the base settings, `YES` in Debug and in the `Profile` configuration (Release, optimized, with the hooks, for the scroll, memory and latency benchmarks). `LaunchMode.detect` ignores `-UITestMode` unless `TestHooks.allowedInThisBuild` is true, so a Release app cannot be put into test mode by its launch arguments, and a benchmark of an optimized build uses `-configuration Profile`. `scripts/check-release-build.sh` fails when the built app's `PestoAllowsTestHooks` is anything but `NO`; `TestHooksConfigurationTests` fails when `Pesto.yml` turns the hooks on anywhere but Debug and Profile; `LaunchModeTests` covers `TestHooks.allowed`.
- **The gate reads the logs.** `scripts/verify.sh` fails on any `warning:` in this repository's `Sources/` or `Tests/` in the Core build (`swift test`), the Debug app build and the hosted-test build, besides compiling Debug with warnings as errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS` does not turn Swift 6's isolation diagnostics into errors). SwiftPM's incremental build prints only the warnings of files it recompiles, so a clean CI run is where the Core build is read in full. Release does not treat warnings as errors, so a new SDK diagnostic cannot block an archive.
- **SwiftLint's analyzer rules are not used** (`unused_import`, `unused_declaration`): they propose removals that do not compile in a package built two ways, and flag App Intents, AppleScript commands and framework overrides. `.swiftlint.yml` carries the lint rules only.
- **Entitlements stay minimal.** `Pesto.entitlements` is empty on purpose (no sandbox, sync off, no Developer ID provisioning until one exists); the Control Center extension has its own sandbox entitlement. `Package.swift` sets no `StrictConcurrency` flag because tools version 6.0 already checks every target strictly.
