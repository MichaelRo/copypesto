# Testing and verification

`scripts/verify.sh` is the gate. Run it before claiming any task done and paste its summary.

```bash
scripts/verify.sh          # lint, Core tests, Debug build, hosted + UI tests, screenshots (about an hour)
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
  polling. It takes about an hour with the UI tests.
- Read only the summary: `.build/verify/<run>/SUMMARY.txt`, or the last 15 lines of the output.
- On a failure, read `.build/verify/<run>/failures.txt`: one line per failing test (`target/Suite/test: message`),
  from the result bundle. Open a log only for a failure whose line does not explain it.
- The gate skips the three suites that only draw pictures (`MarketingScreenshotTests`, `DocScreenshotTests`, `TeaserFramesTests`, about 8 minutes): `make pictures` runs them, and the teaser frames with `-only-testing:PestoUITests/TeaserFramesTests`. They judge no behavior.
- Run the gate on a quiet desktop. XCUITest checks every open app's windows for interruptions on each query, so with an editor, terminals and chat windows open a status-menu test took 130 s instead of 17 s.
- Start exactly one gate, and look first: `pgrep -f verify.sh`. A second `verify.sh` (or a `-only-testing` run) next to a running one locks the shared build database ("database is locked") and every step after it fails for no reason.
- To abandon a gate, kill the script, `caffeinate`, `xcodebuild` and `swift-frontend`, **and the test host it left running** (`pkill -f "xcode-profile.*Pesto.app/Contents/MacOS/Pesto"`); the next `verify.sh` refuses to start next to any running Pesto.
- The first step that fails (Core tests) ends the useful part of a run: read `failures.txt` at once, not at the end of the hour. A timing test ("a cancelled wait returns at once") fails when the Mac is busy with something else (a browser tab or a music player at 100% CPU); start the gate again before blaming code.
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
| `PESTO_UITEST_SEED` | `empty`, `basic` (14 items: text, code, URL, color, images, two masked secrets), `large` (5,000), `everyday` (a dozen clips like a real clipboard, `EverydaySeed`; `mixed` is the benches' history and never changes) or `suggestion` (three text clips, the first pasted 6 times) |
| `PESTO_UITEST_ACCESSIBILITY` | `trusted` or `denied`: the stubbed Accessibility state |
| `PESTO_UITEST_IMPORT_FIXTURE` `otherfile` | Other File… reads a built-in CSV instead of opening a file panel |
| `PESTO_UITEST_AI_FIXTURE` | `1` swaps the on-device model for a fake that answers at once (budget 300 characters) and reports AI as available, so `AIPartsUITests` drives the panel on any Mac |
| `PESTO_UITEST_SUGGESTIONS_LIVE` | `1` makes the shelf-suggestion policy see global hotkeys as live (a UI-test launch registers none), so `ShelfSuggestionUITests` can see a banner; nothing is registered. Pair it with `PESTO_UITEST_SEED=suggestion` (three text clips, the first pasted 6 times) and `PESTO_UITEST_DEFAULT_shelfSuggestionsArmedAt` four days back |
| `PESTO_UITEST_UPDATES` | `1` stands in for Sparkle (never started in a UI-test launch): a check stages a fake 9.9.9 after 0.3 s and the install action writes `update-install` to the command log; `UpdateFlowTests` drives it. Only the app side is covered: Sparkle itself is checked by hand |
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

## Interaction tests: a real pointer, frames, and what you can look at
Anything that depends on where the pointer is or how a layout moves (hover reveals, chips that grow, drag, resize, focus
rings) gets a UI test that drives a real pointer and asserts on frames, not only on state. `AppChipHoverTests` is the
model: it hovers each chip and sweeps across the row in small steps, and checks which chip is open, that chips never
overlap and that the pointer is on the chip that is open.
- Assert what a person would see (frames from the accessibility tree), and name the failure with the numbers (`x=…`,
  `frames […]`). Each element's frame is read separately, so a read that lands mid-change can mix two moments: look again
  once before failing.
- `PointerInteractionTests` covers the card side: rest on a card and its detail opens after a dwell and closes when the pointer leaves, a single click only picks a card (nothing is pasted, the shelf stays), and a fast sweep across the row leaves no detail open. Still to add in this pattern: collection chip drag-reorder and the shelf resize.
- `hover()` is sometimes not delivered when the pointer re-enters a window: move twice (`AppChipHoverTests.hover`).
- Every UI-test run keeps screenshots (`capture(...)`) and a screen recording in its result bundle. Run with
  `-resultBundlePath .build/x.xcresult`, then `xcrun xcresulttool export attachments --path .build/x.xcresult
  --output-path .build/att` and open `manifest.json` for the names. Look at the pictures before saying a layout is right.
- Check flakiness before trusting a new one: `-test-iterations 5 -retry-tests-on-failure`.
- Timing rules (dwell, grace, ease) live in a pure Core type with an injected clock (`ChipHoverIntent`,
  `CardStripDrift`) so they are unit tested; the UI test covers the wiring.

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

**Install, signing and updates (releases are Developer ID signed and notarized, `docs/release.md`)**
- Install from the DMG: download `Pesto-<version>.dmg` from the release, open it, drag Pesto to Applications and open
  it. macOS asks once whether to open an app from the internet; choose Open. Pass: Pesto opens and the setup window
  shows, with no Open Anyway step.
- Download check: `make verify-download DMG=~/Downloads/Pesto-<version>.dmg` (`scripts/verify-download.sh`; its failure
  paths are `VerifyDownloadScriptTests`, its full pass has run once on a real download). Pass: it prints "all checks
  passed" (hash equals the `.sha256` file, valid signature, the Developer ID team, "Notarized Developer ID", both tickets
  stapled). By hand only: the hash also equals the one in the release body and on the download page.
- Local update test (`docs/release.md`, "Each release"): install the previous release, serve a throwaway next one from a
  local appcast, choose Check for Updates… from the menu bar. Pass: it updates to the next version, the history opens with no
  Keychain prompt, and paste still works without granting Accessibility again.
- After a Sparkle bump (`make check-packages`, `docs/release.md`), the local update test above must pass on that build; it is a hand check, nothing automated covers the installer.
- Fresh install: the Accessibility prompt appears, and granting it moves onboarding forward. Pass: the setup window
  advances to the next step as soon as the grant is on.
- Launch at login survives a reboot. Pass: after a restart Pesto is in the menu bar without being opened.
- Paste import with a real library (ADR 0032; every automated test uses a made-up `Paste.db`): Settings → Data → Another
  app's library → Import… → From Paste…, and choose a real `Paste.db`. Pass: the sheet reads "X of Y clips will be
  imported" when a limit applies and says why; Import brings in the collections and the newest history; the summary
  stays on screen after; a second import of the same library says the clips are already in Pesto and adds none; Cancel
  leaves no `pesto-paste-*` folder in the temporary folder (`ls $TMPDIR`); a library over 20,000 clips imports without
  a visible stall in Pesto's menu bar item or the shelf.
- Setup turns Launch at login on (ADR 0024), on a scratch user or after a reset with `PESTO_DEV_RESET=1`: the last setup
  step shows the switch already on and System Settings → General → Login Items lists Pesto. Pass: restart and Pesto is in
  the menu bar; turn the switch off in Settings, restart, and it is not. A Pesto outside Applications shows macOS's reason
  under the switch instead. A UI test cannot check this: its launch never registers a login item.
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

**Shortcuts and pasting**
- JSON and Markdown in Paste As… (2026-11-06, ADR 0033): copy rows from a spreadsheet (Numbers or Excel), a table from a
  web page, formatted text from Pages, Notes and Google Docs, and a one-line JSON document. Right-click each, or press ⌘K.
  Pass: the rows lead *Paste As…* and *Copy As…* only where they fit (prose, a picture and a hidden clip show none),
  the pasted text is what the guide says, and the menu opens without a pause on a 1 MB table. With screen sharing on
  or Hide Clip Contents, the covered card's menu has no Paste As… at all.
- Copy Recognized Text (2026-11-06, ADR 0034): screenshot a page of text, a receipt and a picture with no text (⇧⌃⌘4 to
  the clipboard). Wait for each card to finish loading. Pass: the menu of the text pictures has *Copy Recognized Text*
  after Copy, pasting it elsewhere gives all the text (not only the first 500 characters), the plain picture has no
  entry, and a screenshot of a key or card number has none and is masked. Hover the text picture and move straight to
  the *Copy Text* button: the card stays open on the way, a wash shows behind the button with the same space on both sides of the label (ADR 0036), one click says *Copied* for
  two seconds, and the shelf under the card still takes clicks. The copy makes the text a new clip at the front of the shelf and the picture stays where it is (ADR 0037): the shelf gains a card within about 200 ms, so look that the focus ring and the hover card do not jump under the pointer. Copy the same text again: the clip you have moves to the front, no second one. Reduce Motion on: no animation. With screen sharing on
  or Hide Clip Contents the covered card has no hover card and no entry. The synthetic click test
  (`HoverCardClickTests`) cannot tell a real first click in a never-key window from a sent event: check one by hand.
- ⌘[ and ⌘] (2026-11-04): with a 5,000-clip history and three collections, hold ⌘] across all of them and back, and
  compare with 1.2.0. Pass: each collection's clips appear in one step, with no flash of the previous collection's
  clips, and no stutter (`LargeHistoryPerformanceTests` times the filtering; the redraw is only seen by eye).
- Quick Look (⌘Y): copy a GIF from a browser, a page of a PDF and a WebP picture, and two files in Finder. Pass: ⌘Y shows
  the GIF animating, the PDF page and the picture, not text, and the arrow keys step between the two files. Esc closes
  only the preview (the shelf stays), arrow keys then move between clips and open no preview, and ⌘Y opens it again. Its
  size (a share of the display, centred) is `QuickLookPanelSizingTests`.
- AI result Paste (needs Apple Intelligence): run an action on a text clip and press Return. Pass: the answer lands in
  the app you were in, also after reading it for over 20 seconds; Copy Result files the answer in the history, Paste does
  not, and the clip it was made from moves to the front.
- Long Summarize (needs Apple Intelligence): run Summarize or Key Points on a very long text. Pass: an answer for the
  whole text arrives (the guide says it is read a part at a time) in a panel as tall as the answer, with Close, Paste, Copy Result
  and Done in one style.
- ⇧⌘V from TextEdit, VS Code, Chrome and Slack. Pass: the shelf and the caret quick menu open, and pasting lands in each.
- Paste a text, link, picture and file from the shelf into TextEdit, Safari, Chrome, Slack, Terminal and VS Code (Return
  and double click). Pass: every paste lands; none does nothing.
- The shelf's memory (ShelfContextPolicy, 90 seconds): open a collection and search, close the shelf, reopen within a
  minute and again after two. Pass: within 90 seconds the collection and the search stay; after 90 seconds the shelf is on
  All and the search is empty. A paste clears the search immediately.
- Edit shortcuts in the shelf's search field: ⌘X cuts, ⌘V pastes, and caret movements (← → ⌘← ⌘→ ⌥← ⌥→ ⌥⌫ ⌘⌫) move and
  delete across words and to the ends. Pass: each edit shortcut mutates the search field without clobbering the shelf.
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
- The filter bar (ADR 0023), on a real history, on the 14-inch display and a wider one, in Light and Dark. Pass: the
  bar fits without scrolling; Tab walks Kind, Format, Today, Yesterday, More, From and Sensitive; Return opens Format, More
  and From as native menus, an arrow key moves in the menu and Return picks; picking a chosen value again, or Any Time, Any
  App or Any Format, clears it (what a chip says is `FilterMenuLabelTests`). With VoiceOver on, Space on
  each of the three menu chips opens its menu (the runner cannot press a pop-up with VoiceOver).
- A snippet with fill-ins (ADR 0017), on hardware, in Mail, Notes, a browser field and Terminal: paste it from the shelf, from
  a `⌃N` shortcut and with Paste the Previous Clip. Pass: the prompt opens over the app without taking the app's place in
  the Dock or menu bar, typing works at once, Return pastes the filled text into the same field the caret was in within
  about 300 ms of Return, Esc pastes nothing, and a second paste while the prompt is up closes it. Locking the screen with ⌃⌘Q leaves the prompt open (checked by hand 2026-10-28, accepted: it is still there after the unlock).
  Also paste one by one with a fill-in snippet in the selection: the prompt comes before the first clip and ⌘V never waits.
- App chips and URL card actions: hover across the app filter chips slowly and fast (`AppChipHoverTests` moves a real pointer
  across them and keeps screenshots and a screen recording in the result bundle). Pass: chips are steady 24 pt icons;
  resting on one for a moment opens its name in place and pushes the chips after it to the right, never over them;
  moving to the next chip switches at once, a quick pass opens nothing, and the pointer never ends up on a chip it did not
  choose;
  right-click a URL card: "Copy Page Title" and "Copy Preview Image" appear
  directly under "Copy".

**Privacy**
- A copy from 1Password or Apple Passwords. Pass: it is not captured.
- Touch ID lock and unlock, the password fallback, and one shared timer for protected actions. Pass: the lock asks for
  Touch ID, falls back to the password, and a protected action inside the "Ask for Touch ID again after" window asks nothing.
- Show on a hidden clip with Use Password…. Pass: the shelf stays open while the system dialog is up and the clip shows
  afterwards (a known defect while the Touch ID prompt itself is up, filed as an issue).
- A share from Google Meet in Chrome (whole screen or a single window) with Hide During Screen Share on (Chromium shows
  the floating sharing bar window for both, ADR 0003). Pass: the cards are covered within 3 s.
- Hide Clip Contents from the menu bar, and as a Shortcuts action and Focus filter. Pass: the cards are covered each way.

**Look and feel**
- The menu-bar icon (2026-10-22): with Appearance forced to Dark on a Mac set to Dark whose wallpaper makes the menu bar
  light (or the reverse), then change the wallpaper, switch Spaces and wake the Mac. Pass: the Pesto icon always matches
  the other menu-bar icons; hiding the menu-bar icon works.
- Each theme in light and dark with its icon. Pass: text, accent and the icon read on every one.
- Wallpapers (also with Settings → Appearance → Shelf surface on Glass, then Solid; ADR 0035): System Settings → Appearance with the transparency slider at minimum, middle and maximum, Reduce
  Transparency, Increase Contrast and Reduce Motion, over the lightest and darkest wallpaper. Pass: the shelf, Settings
  and the quick menu stay readable, the focus ring is visible (A-14), and the hover card does not scale (the card header's age is
  `CardHeaderTimeContrastTests`, D-07).
- Shelf surface (ADR 0035): in Settings → Appearance choose Solid, then Glass, in each theme, light and dark, with a white
  window and a busy wallpaper behind the shelf, and once with Reduce Transparency on. Pass: on Solid a light card's edge
  reads on the shelf and the shelf does not vanish into a white window behind it; the wash follows the focused card on
  both; with Reduce Transparency on, Solid is selected and disabled with the reason, and *Open System Settings…* opens
  the Display pane of Accessibility (the URL is unverified).
- Text size: set the largest text size and open the shelf, Settings and setup. Pass: no text is cut off or overlaps.
- Settings on two displays (2026-11-04; the rule is tested in `SettingsWindowFrameTests`, the displays are not): with
  the shelf on one display, choose Settings from its gear; with the shelf closed, choose Settings from the menu-bar
  icon with the pointer on the other display. Pass: Settings opens on the display in use each time, at the size it was
  closed at, and a window already open is only brought forward, not moved.
- Settings → Data, the Backup and Sync cards (ADR 0022), on hardware: in a narrow Settings window, in Dark and Light, with
  sync available and with it unavailable (signed out of Apple Account, or offline); turning either switch on opens its
  set-up sheet and Cancel leaves it off.
- The color panel from the shelf, and Paste the previous clip after an iPhone copy. Pass: the panel opens, and the
  previous clip pastes.
- Import offer with two or more clipboard managers really installed (Paste and Maccy). Pass: (the sentence is `ImportOfferTests`) *Choose…* opens Settings → Data scrolled to **Found on this Mac**
  with each app's own icon, *Import…* on a row asks for Touch ID and a file for that app only, and the row then says "Imported N clips".
- Card typography (`docs/design/card-typography.md`, option B): copies from three different apps on every theme in light
  and dark at Small, Medium and Large. Pass: the header names the app at a glance (the 32% wash is enough on Parmesan and
  Pine nut), the text is the loudest thing on the card, and a long text shows 4, 5 and 6 lines with a clear gap above
  the footer. If the app color is lost on a theme, fall back to option A.
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

**Data and performance**
- Footprint after days of real use: `footprint <pid>` (peak as well as current), and `ps eww <pid> | tr ' ' '\n' | grep
  Malloc` on a launch from Finder. Pass: steady state under 150 MB.
- `make bench-latency open 7` three times (the only check that has the retention pruner, a 5,000-clip history and a copy
  made while the shelf was closed; `OverlayPerformanceTests` has none of them). Pass: the median is under 100 ms each time.
- `make bench-scroll`. Pass: it prints `shelf scroll travel` of at least 300 points for both histories (a run in which
  the shelf did not move fails) and stays within the scroll budget. A trace that hangs is stopped after two minutes
  (`scripts/run-with-deadline.sh`) and that history fails while the next one still runs; `xctrace` took about three
  minutes to save a trace on 2026-11-06, so on a Mac under load run `PROFILE_RECORD_DEADLINE=600 make bench-scroll`.
  To compare the shelf surfaces (ADR 0035) put `PESTO_UITEST_DEFAULT_shelfSurface=glass` (or `solid`) before
  `make bench-scroll` or `make bench-latency`; for a UI test, `TEST_RUNNER_PESTO_BENCH_SHELF_SURFACE=glass`.
  To see it work, quit `xctrace` (`pkill xctrace`) during a pass. Pass: that history fails with *xctrace record
  failed*, the next history still runs, and `make bench-scroll` exits non-zero.
- `make bench-latency all 7`, `make bench-undo` after a change to Undo, and `make bench-sync` after a change to sync. Pass: both stay within budget.

**Undo** (ADR 0008; `make bench-undo` for the numbers)
- Shelf at the bottom and at the top: delete a clip or collection, and press ⌘Z. Pass: the undo banner shows and ⌘Z brings it back in the same place.

**Cards, cover, No Results and the click hint (ADRs 0026 to 0029)**
- Content-first cards: copy a picture, a GIF, a color, a short sentence and a plain link, and look at the shelf in light
  and dark. Pass: the picture and GIF fill the card with readable text over it, the GIF moves where it did before, the
  color card's text is readable on a light and a dark color, short text is larger than a paragraph (24 pt up to 24 characters, 18 pt to 48, first
  lines level across neighbours, nothing clipped under the header at the largest system text size), and a plain link
  leads with its host and shows no query. PDF, video, code and long-text cards look as they did.
- Scroll 5,000 clips of mixed kinds (`make bench-scroll` covers the numbers). Pass: nothing stutters on the picture and
  GIF cards, and Activity Monitor shows memory under the budget after a minute of scrolling.
- A covered card (screen share, Hide Clip Contents, the content filter's blur): a click or Return still pastes it without
  showing it. What it draws is the `test_coveredCard_showsNumberKindAndAge` baseline, what its menu and VoiceOver actions
  offer is `CardConcealmentTests` and `CoveredMenuWiringTests`.
- Banners: an import offer, a shelf suggestion and the click hint. Pass: they share one capsule style and none covers a card.
- No Results VoiceOver wording (`NoResultsAdviceUITests.test_tabThroughTheChips_reachesClearFiltersAndReturnPressesIt` covers the Tab walk): with VoiceOver on, press Clear Filters or Clear Search. Pass: VoiceOver says "Filters cleared" or "Search cleared".

## Two Macs: sync
Run once at the end, on two Macs signed in to the same Apple Account with iCloud Drive on, with a build from `make release SYNC_PROFILE=…` (iCloud Keychain key) and, separately, with the daily self-signed build (this-device key). Never use a Mac whose history matters: turn sync on only after a backup. Pass means every line holds.

**Measure first** (`scripts/sync-latency/`, once written): a small and a 5 MB file written on A arrive on B (p50 and p95 in `docs/perf/sync-latency-2026-11.md`), awake, after sleep, in Low Power Mode, with Optimize Mac Storage on. It sets the poll interval.

**Set up.** On A: Settings → Data → Sync with my other Macs → Turn On Sync. Pass: the sheet names the folder and what leaves the Mac; the recovery key is shown once and can be shown again behind Touch ID. On B: the same switch. Pass with the profile build: B finds the sync and offers to join with both counts and no key typed. Pass with the self-signed build: B asks for the key; the recovery key joins it; *Ask Another Mac* shows eight words on both Macs and A allows it.

**Flow.** Copy text on A: it appears on B (time it). Copy a picture, a link, a file, a color. Pin a clip and rename a title on A: B follows. Delete on A: it is gone on B and a restore of an old backup on B does not bring it back. Copy the same words on both: one clip. Paste a clip from a collection on A before B has joined, then set B up: B lists that collection in A's order, and a
paste on B does not move the clip inside it (ADR 0021). Edit a snippet on both at nearly the same time: the later edit wins on both. Turn B's Wi-Fi off, copy on both, turn it on: both converge and nothing is lost.

**Secrets.** Copy a password-manager entry, a card number and a JWT on A: none reach B. Turn on *Also sync clips with secrets*: they do, hidden, and need Touch ID on B. Turn it off: they leave B.

**Repairs.** Pause on B, copy on A, Resume: B catches up. Change… the folder on B to a local folder: sync stops, the old folder is untouched, set-up opens. Reset Sync on A: B shows *New key needed* (or rejoins with iCloud Keychain) and both converge on the new key. Leave Sync on B: only B's files go from the folder, B's clips stay, A keeps everything. Quit and relaunch both: sync resumes with no sheet.

**Health.** The status line says what is true: *Receiving from your other Macs* while files download, *Waiting for the Folder* while a file is still arriving, *Folder Missing* with the folder moved, the *iCloud Keychain Is Off* sheet after turning it off in System Settings, *Refused* with a reason after changing a byte of a `.pestolog`. Idle CPU stays under 0.5% and memory under 150 MB. System Settings → Network shows no connection from Pesto.

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
- **A test that picks a clip by its position on the shelf breaks whenever the seed changes** (three times in one afternoon). The shelf's order is not the seed's order: a clip that appears twice in a seed is saved once and jumps to the front, and Return/Space picks follow what is on screen. Print the real order before editing a position (a temporary test that walks the shelf and prints each card's label) instead of guessing; prefer picking by content.
- **A change to a shared test helper (`PestoUITestCase.launch`) reaches every UI test**, including ones the change was not written for: a "stale ready marker" cleanup made each launch wait for real readiness and broke an unrelated selection-bar test that only passed because it started early. Keep a fix local to the test that needs it, or run the suites that use the helper before committing.
- **`PasteRecorder` writes no text for a link or a picture** (`kind: nonText`), so `pastedTexts()` drops those pastes. Count lines of `paste-log.jsonl` when a test pastes something other than text.
- **A git worktree has a `.git` *file* holding the path of the main checkout**, which a scan of top-level files (`PersonalDataTests`) used to flag as the owner's home folder.
- **A recompile can surface old warnings.** The gate counts warnings as failures, and an incremental build had hidden three for weeks.

- **A seed profile a bench measures is frozen.** `.mixed` (`MixedSeed`, 1,200 clips) is what `make bench-scroll` and `make bench-shelf` compare over weeks; pointing it at a different history in the middle of a design spike nearly invalidated every recorded number (2026-11-13). A different look (an everyday clipboard for pictures) is a new `SeedProfile`. `MixedSeedTests.whenMixedProfile_thenItIsExactlyMixedSeed` fails on a changed size or content.

## Test hooks, warnings and entitlements

- **Test hooks are an `Info.plist` property.** `PestoAllowsTestHooks` is `$(PESTO_ALLOWS_TEST_HOOKS)`, set in `Pesto.yml`: `NO` in the base settings, `YES` in Debug and in the `Profile` configuration (Release, optimized, with the hooks, for the scroll, memory and latency benchmarks). `LaunchMode.detect` ignores `-UITestMode` unless `TestHooks.allowedInThisBuild` is true, so a Release app cannot be put into test mode by its launch arguments, and a benchmark of an optimized build uses `-configuration Profile`. `scripts/check-release-build.sh` fails when the built app's `PestoAllowsTestHooks` is anything but `NO`; `TestHooksConfigurationTests` fails when `Pesto.yml` turns the hooks on anywhere but Debug and Profile; `LaunchModeTests` covers `TestHooks.allowed`.
- **The gate reads the logs.** `scripts/verify.sh` fails on any `warning:` in this repository's `Sources/` or `Tests/` in the Core build (`swift test`), the Debug app build and the hosted-test build, besides compiling Debug with warnings as errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS` does not turn Swift 6's isolation diagnostics into errors). SwiftPM's incremental build prints only the warnings of files it recompiles, so a clean CI run is where the Core build is read in full. Release does not treat warnings as errors, so a new SDK diagnostic cannot block an archive.
- **SwiftLint's analyzer rules are not used** (`unused_import`, `unused_declaration`): they propose removals that do not compile in a package built two ways, and flag App Intents, AppleScript commands and framework overrides. `.swiftlint.yml` carries the lint rules only.
- **Entitlements stay minimal.** `Pesto.entitlements` is empty on purpose (no sandbox, sync off, no Developer ID provisioning until one exists); the Control Center extension has its own sandbox entitlement. `Package.swift` sets no `StrictConcurrency` flag because tools version 6.0 already checks every target strictly.

## The first-open bench in the gate (`first open, imported`)
`scripts/bench-first-open.sh 3 imported` launches the app three times with the pre-warm off and three with it on, interleaved, opens the shelf once
per launch and fails when the pre-warmed median is 100 ms or more (85.8 ms measured on 2026-11-12, against 221.6 ms cold). It is the figure
the website's speed strip states, so a change to the number there starts here.

## The shelf bench in the gate (`shelf bench, imported`)
`scripts/verify.sh` runs `SEEDS=imported RECORD=1 scripts/bench-shelf.sh` after the memory steps (not with `--fast` or `--skip-ui`;
it needs an unlocked Mac). It judges the imported-shaped history (`scripts/profile-scroll/check-shelf-budget.py`): view bodies per
arrow press tightly (about 3 cards, 1 grid, 0 overlay; a focus move that re-runs the overlay or every card fails), commit times by
a multiple of a developer Mac's (arrow step p95 35 ms, collection switch p50 80 ms and p95 100 ms, held ⌘] key-to-commit p95 50 ms).
Nothing fails under CI. `RECORD=1` appends the run to `docs/perf/history/shelf.jsonl` with the machine; `python3
scripts/profile-scroll/perf_history.py trend` prints the last runs of each figure and flags one more than 25% (and 3 ms) worse than
the median of the previous five on the same machine. Commit the history file with the change that produced the numbers.
