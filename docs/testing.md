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
PASS  iOS unit + UI tests (iPhone, iPad)   iPhone unit=427 iPad unit=427 ui=19
screenshots: .build/ui-screenshots/20260924-185508 (19 PNGs)
RESULT: PASS
```

A green summary has to mean the tests ran. `scripts/verify_judge.py` fails the gate when fewer tests ran than its floors
(Core 950 Swift Testing and 30 XCTest, hosted 270, UI 130, snapshots 30, iOS 380 unit tests on each simulator and 18 UI
tests) or when a test was skipped that `scripts/verify-allowed-skips.txt` does not name (a Mac without the on-device
model, memory deltas on CI). The iOS app runs last, on the iPhone 17 and then the iPad Air 11-inch (M4) simulator; an
iOS UI test that belongs to one device skips on the other, so it counts as skipped only when it passed on neither. A
CI runs only the iPhone's unit tests (its iPad simulator hangs, and both devices run past the job's time limit), and only when
something the iOS app builds from changed (`detect-changes` sets `PESTO_SKIP_MOBILE`); a pull request's run also skips
the Release build (`PESTO_SKIP_RELEASE_BUILD`), which the local gate keeps,
and records SKIP when the runner has no iPhone simulator; a developer Mac without either simulator fails the step. `scripts/verify-rerun-failed.sh` re-runs only the Mac's tests: to re-run a failed iOS test, run its `-only-testing` on the simulator named in the step's log (`mobile-phone.log`, `mobile-pad.log`), then the whole gate. The script
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
- Download check: `make verify-download DMG=~/Downloads/Pesto-<version>.dmg` (`scripts/verify-download.sh`; its failure
  paths are `VerifyDownloadScriptTests`, its full pass has run once on a real download). Pass: it prints "all checks
  passed" (hash equals the `.sha256` file, valid signature, the Developer ID team, "Notarized Developer ID", both tickets
  stapled). By hand only: the hash also equals the one in the release body and on the download page (or pass `--check-live <version>`).
- After a Sparkle bump (`make check-packages`, `docs/release.md`), run the local update test (`scripts/vm/vm-sparkle-update.sh` or on a scratch Mac) on that build; it must update to the next version with no Keychain prompt and keep paste working without granting Accessibility again.
- Real DMG Gatekeeper, Launch at Login reboot, missing Keychain recovery, and real TCC prompt flows are automated in `scripts/vm/` (Tart macOS VMs) and only need a manual pass when changing notarization, entitlements, or Sparkle major versions.

**Shortcuts and pasting**
- Copy Recognized Text (2026-11-06, ADR 0034): screenshot a page of text, a receipt and a picture with no text (⇧⌃⌘4 to
  the clipboard), wait for each card to finish loading, and check *Copy Recognized Text* and *Copy Text* on hover (`HoverCardClickTests` cannot tell a real first click in a never-key window from a sent event: check one by hand). Pass: pasting gives all the text, plain/secret pictures have no entry, *Copied* shows for two seconds, the shelf under the card still takes clicks, Reduce Motion has no animation, and screen sharing/Hide Clip Contents hides both.
- ⌘[ and ⌘] (2026-11-04): with a 5,000-clip history and three collections, hold ⌘] across all of them and back (`LargeHistoryPerformanceTests` times the filtering; `scripts/check-collection-switch-flash.sh` checks frames; the redraw feel is checked by eye). Pass: each collection's clips appear in one step with no flash or stutter.
- AI result Paste & Long Summarize (needs Apple Intelligence on hardware): run Summarize or Key Points on a short clip and a very long text, wait over 20 seconds on the result panel, and press Return. Pass: the answer for the whole text lands in the target app, Copy Result files it in history, Paste does not, and the source clip moves to the front (`AIEvalsTests` / `AIResultDelayedPasteUITests` cover the deterministic stub path).
- ⇧⌘V, Return, and double-click paste into real third-party desktop apps (`scripts/multi-app/` and `scripts/vm/vm-tcc-matrix.sh` cover TextEdit, Notes, Chrome, Edge, VS Code; check Slack and Terminal by hand if changed). Pass: every paste lands.
- Drag cards out of the shelf onto a real app window behind the glass (e.g. Claude desktop input, Notes, Safari address bar, Desktop, Finder — `scripts/drag-and-hover/` covers the pointer leave/re-enter clearance). Pass: the shelf goes click-through outside the panel, drops land as expected, holding > 3 s mid-drag keeps the shelf open, and Esc cancels cleanly.
- Copy a GIF with Copy Image in live Chrome, Arc, and Edge (`BrowserGIFDumpTests` replays captured dumps; spot-check live browsers after major browser updates). Pass: it plays on the card.
- Remote photos and Paste the Previous Clip after an iPhone copy (hardware Universal Clipboard, iOS): copy a photo or PDF on the iPhone, then paste a file clip whose file you deleted (`RemotePastePreviousTests` and `DeletedFilePasteTests` cover the core/hosted logic). Pass: nothing from the phone is kept, "Left out of your history" counts it in Settings → Privacy, ⌘V still pastes it, and a toast warns for the deleted file.
- A snippet with fill-ins (ADR 0017), on hardware in Mail, Notes, a browser field and Terminal: paste from the shelf, `⌃N`, and Paste the Previous Clip (including Paste One by One with a fill-in in the selection). Pass: prompt opens without stealing Dock/menu bar, Return pastes within ~300 ms, Esc pastes nothing, and ⌃⌘Q lock keeps the prompt open.
- App filter chip hover feel (`AppChipHoverTests` moves a real pointer and records video in the result bundle): spot-check by hand on a real history to confirm the hover expansion feels steady.

**Privacy**
- Copy from 1Password or Apple Passwords (spot-check live apps after OS/app updates; `ExclusionRulesTests` and `BundleIDDriftTests` cover the bundle IDs). Pass: it is not captured.
- Real Touch ID hardware prompt & password fallback (`ShelfAuthenticationTests` and `BiometricLockOverlayUITests` cover the grace timer and UI-test flow; spot-check real Touch ID sensor once per release). Pass: Touch ID unlocks, password fallback works, and the grace window is shared across protected actions.
- Live Google Meet screen share in Chrome (whole screen and single window, `ScreenShareDetector` logic is unit-tested). Pass: cards cover within 3 s when sharing starts.

**Look and feel**
- Menu-bar icon & themes across real macOS wallpapers, Spaces, and display wake (`MenuBarWakeTests` and `BackdropContrastUITests` cover the programmatic checks; spot-check by eye on physical desktop). Pass: icon matches system menu-bar items, and shelf/cards remain readable across Light/Dark, Glass/Solid, Reduce Transparency, Increase Contrast, and Reduce Motion (`CardMetaLineContrastTests`).
- Settings on two physical displays (`SettingsWindowFrameTests` and `scripts/virtual-display/run.sh` cover virtual/frame placement). Pass: Settings opens on the active display at its saved size.
- Settings → Data Backup and Sync cards on hardware with a signed-in vs. signed-out Apple Account and offline state. Pass: narrow Settings layout reads cleanly and Cancel leaves switches off.
- Card typography (`docs/design/card-typography.md`, option B) and 5,000-clip live scroll feel (`make bench-scroll` and `LargeTextSizeSnapshotTests` cover numbers and baselines; spot-check by eye for stutter).
- Collection chips (drag reorder and drag-a-clip-onto-a-chip): drag a chip along the row and drop a clip onto a chip (`CollectionChipKeyboardReorderUITests` covers Move Left/Right). Pass: cursor never shows not-allowed, the dragged chip leaves an empty slot, chips slide without jitter, and dropping keeps the order.
- Onboarding card strip: scroll it by hand with a trackpad and let go. Pass: it rests about a second, drifts on smoothly, and stays still with the pointer resting on it.

**Accessibility**
- Live VoiceOver sweep on hardware (`scripts/test-voiceover.sh` drives `VoiceOver.sdef` on the shelf; `VoiceOverContractUITests`, `LostKeyAXTreeUITests`, `CardAccessibilityTests`, and `NoResultsAdviceUITests.test_tabThroughTheChips_reachesClearFiltersAndReturnPressesIt` cover AX contracts). Spot-check Settings with live VoiceOver (`PopUpMenuButton`, "Options for …", Privacy disclosure, "Filters cleared" / "Search cleared" announcements, and lost-key restore window).

**Data and performance**
- `make bench-latency open 7` three times, `make bench-latency all 7`, `make bench-scroll`, `make bench-undo`, `make bench-sync`, and `scripts/soak-memory.sh` (steady-state `footprint` under 150 MB).

**Undo** (ADR 0008; `TopShelfUndoUITests` and `make bench-undo` cover automated checks)
- Spot-check top-edge shelf delete + ⌘Z visually on physical display.

**Cards, cover, No Results and the click hint (ADRs 0026 to 0029)**
- Content-first cards visual spot-check on physical display (`test_coveredCard_showsNumberKindAndAge`, `CardConcealmentTests`, `CoveredMenuWiringTests`, `FilterMenuLabelTests` cover automated checks).

## The Mac widget (a release signed with both profiles)
Only an exported build made with `SYNC_PROFILE` and `WIDGET_PROFILE` can show it (ADR 0059, `docs/release.md`); the
snapshot logic is covered by `WidgetSnapshotKeeperTests`, `WidgetSnapshotGateTests`, `WidgetSharingTests` and the
`pesto://clip` cases of `AutomationURLHandlerTests`. By hand, on that build:
- `scripts/check-widget-signing.sh` passes; the launched app logs no `AMFI` or "No matching profile found", and sync
  still finds its iCloud Keychain key.
- Recent Clips is in the widget gallery (small, medium, large); a development build's gallery has only the control.
- With a widget placed, the shelf opened once, `~/Library/Group Containers/group.net.copypesto.pesto/widget-snapshot.pestowidget`
  exists and starts with `PESTOWGT`; removing the widget removes it within ten minutes or the next shelf open.
- Copy (the default) puts the clip on the clipboard and moves it to the front; note whether focus returns to the app
  you were in. Show opens the shelf at it; Open on a link clip opens the browser.
- History Lock on: the widget says Locked. Hide Clip Contents, or a screen share with the setting on: "Clip contents
  hidden". A new secret never appears.
- On the first profile-signed build, on a Mac that already synced: the existing sync key still opens (sync exchanges
  without asking for the recovery key or an approval), so adding the app group and the widget's Keychain group left
  the app's validated entitlements and its iCloud Keychain item alone.
- Readability in every rendering mode: on the Mac with the desktop dimmed (another app in front, widgets drawn in the
  desktop's muted style), and on iOS with the Home Screen set to Tinted and to Clear (`widgetRenderingMode` accented
  and vibrant): the text, the foot line, a color card's hex and the Locked and Hidden messages stay readable.

## Two Macs: sync
Run on two physical Macs signed in to the same Apple Account with iCloud Drive on (two-Mac local-folder mechanics are automated in `TwoProcessSyncTests` and `scripts/vm/vm-two-mac-sync.sh`; only real iCloud Drive daemon sync, `Optimize Mac Storage`, and iCloud Keychain cross-Mac join require physical Apple Accounts).
- Measure small and 5 MB arrival (`scripts/sync-latency/run-remote.sh`), awake, after sleep, in Low Power Mode, and with Optimize Mac Storage on.
- Verify real iCloud Keychain auto-join, 8-word pairing, secrets toggle, Reset Sync, Leave Sync, and iCloud status banners (*Receiving*, *Waiting for the Folder*, *Folder Missing*, *iCloud Keychain Is Off*, *Refused*). Pass: idle CPU < 0.5%, memory < 150 MB, and no unexpected network connections in System Settings → Network.

## The iPhone and iPad app

`make test-mobile` runs the iOS test target on an iPhone and then an iPad simulator (`IPHONE_SIMULATOR`, `IPAD_SIMULATOR`
name them); `make test-mobile-ui` runs `LibrarySmokeUITests`: two iPhone tests (copy, search, Pinned, the detail sheet;
dark and an accessibility text size) and one iPad test (sidebar, a collection, the inspector, the chip row with the
sidebar hidden), each skipping on the other idiom. A `-UITestMode` launch of the iOS app honors the flag only because
`Sources/Resources/PestoMobile-Info.plist` carries `PestoAllowsTestHooks`, and it seeds a clip of each kind through
ingest, pins one and files one in the collection "Trip" (`MobileSeed`, Debug only) unless `PESTO_UITEST_SEED` is
`empty`. `PESTO_UITEST_DEFAULT_appearanceMode=dark` gives a dark launch and `-UIPreferredContentSizeCategoryName
UICTContentSizeCategoryAccessibilityL` a large text size. The iPad test turns the simulator to landscape, where the split
view shows its sidebar; the screenshot it attaches comes out rotated. After a long press or a sheet, XCTest waits about
60 seconds for an "animations complete" notice that never comes (the app is idle, measured at 0% CPU), so each of the
longer tests takes over two minutes. The tests are hosted in the iOS app, so the runtime seams keep them off real data as on the Mac. The target
also compiles `Tests/PestoCoreTests/Sync`, which proves the sync format and its keys on iOS; a helper there that needs
AppKit is left out in `Pesto.yml`. The gate does not run these tests yet. A simulator has no iCloud Keychain, no real
iCloud Drive and no Face ID hardware: those are hand checks on a device. `LayoutSwapUITests` (iPad) forces the library's size class with `PESTO_UITEST_SIZE_CLASS` and flips it with a control only a `-UITestMode` Debug build carries (`UITestLayout`), because XCUITest cannot resize an iPad window: it proves an unsaved Edit Text draft, the search text, the open clip and the first visible card (`PESTO_UITEST_EXTRA_CLIPS` seeds filler notes so the grid scrolls) survive the swap there and back; a real Split View resize stays a hand check. `LibraryEditingUITests` (iPhone) edits a clip's
text in the detail, goes from Dark back to System and samples the ground and the Settings sheet for light pixels,
picks a collection's icon, and shows the "Add what you copied" banner. The capture cover is also on screen in `PrivacyUITests` through `PESTO_UITEST_DEFAULT_uitestForcesSceneCapture=true` (with `screenSharingPrivacy=true`), a DEBUG-only switch honored only in `-UITestMode`: the simulator never reports a real capture (UIKit's `sceneCaptureState` trait can be overridden by an app but not set from outside, `simctl io recordVideo` does not change it, and the simulator's external display is not a mirror), so a real recording, mirroring and AirPlay stay hand checks. Pass 2 adds `MobileSnippetTests`, `MobileRetentionTests`, `MobileLinkPreviewTests`, `GIFAddressTests`, `CardCopyActionsTests`, `MobileAddClipboardTests` and the date and Other Devices chips in `LibraryFilterTests`; each uses fakes, temp folders and a fetcher that counts calls, never the network. The History Lock and the cover (ADR 0054) are unit-tested in `MobileHistoryLockTests` and `MobileContentCoverTests` (a lock built with closures for its setting and timeout, never the real preferences) and on screen in `PrivacyUITests` (iPhone: the lock screen with no card, `PESTO_UITEST_DEFAULT_biometricLockEnabled=true` and `uitestAuthenticationGranted`; Hide Clip Contents). `simctl io recordVideo` does not change the scene's capture trait, so the cover during a real recording, mirroring or AirPlay, Face ID and the App Switcher picture are hand checks on a device. The background sync refresh is unit-tested
(`SyncExchangeTests`: the scheduling decision, the declared task, the same exchange as pull to refresh); a real
background launch is a hand check on a device.

The share extension's inbox is tested in Core on the Mac (`SharedInboxTests`: sealing, refusals, the writer's limits;
`InboxDrainTests`: the drain through ingest on a file-backed store, with the temp group folder scanned for plaintext)
and in the iOS app (`MobileInboxTests`, `MobileShortcutsTests`), always with a temp folder and `MemorySecrets`, never
the real app group or Keychain. `PestoShare` itself has no test target: the system share sheet cannot be driven from a
UI test of Pesto, so sharing from Safari or Notes into Pesto is a hand check (build, launch Pesto once, share, reopen).

The AutoFill set (ADR 0051) is tested in Core on the Mac (`QuickInsertSelectionTests`: what may enter, the order and
the bounds; `QuickInsertEnvelopeTests`: sealing, refusals, no plaintext in the bytes; `QuickInsertMenuTests`: the
picker's sections, search and empty states) and in the iOS app (`MobileQuickInsertTests`: off means no file and no
Keychain read, a history change and leaving the foreground write it, Clear History empties it, a clip made secret
leaves it, and the extension's read path opens what the app wrote), with a temp folder and `MemorySecrets`.
`PestoAutoFill` has no test target. In the iOS 27.2 simulator the extension is registered (`pluginkit`) and the edit
menu offers AutoFill, but Settings > General > AutoFill & Passwords did not list Pesto (nor with `ProvidesPasswords`
added as an experiment), so picking a clip through the real AutoFill sheet is a hand check on a signed device build.

The keyboard (ADR 0061) reads the same set. Its decisions are tested in Core (`KeyboardMenuTests`: the four states,
that without Full Access the set is never loaded and the order of sections; `QuickInsertEntryLabelTests`: a snippet
shown as it would insert; `QuickInsertEnvelopeTests`: the file's modification date that
tells the keyboard to re-open it, and `openSet`, the read AutoFill and the keyboard share). The iOS test target compiles
`Sources/MobileKeyboard` and `KeyboardRenderingTests` draws each state at iPhone and iPad width, light and dark, into
`.build/keyboard-renders` (in a window of the app's scene: `ImageRenderer` draws its UIKit parts as placeholders). A
UI test cannot add a keyboard in iOS Settings or grant it Full Access, so the keyboard in another app is a hand check
on a device (below).

The widget snapshot (ADR 0052) is tested in Core (`WidgetSnapshotSelectionTests`: what may enter, the order and the
bounds, the fullest snapshot still sealing; `WidgetSnapshotSealingTests`: refusals, no plaintext in the file, neither
file's key opening the other; `WidgetContentTests`: each family's clips and state and the timeline's moments;
`WidgetLinkTests`: the three accepted link shapes; `WidgetTapTests`: what each setting does to each kind, and the http(s)-only rule) and in the iOS app (`MobileWidgetTests`: no widget means no file and no
Keychain read, a history change writes it, Clear History empties it, a clip made secret leaves it, the last widget
removed takes the file and key, the widget's reader opens what the app wrote, a copy link copies, a show link opens the detail and an open link hands only a web address to the browser, and an in-place copy writes the whole text),
with a temp folder, `MemorySecrets` and a stand-in for `WidgetCenter` (`WidgetTarget`). The iOS unit-test target compiles
`Sources/MobileWidget` (all but the `@main` bundle), and `WidgetRenderingTests` draws every family and state in light
and dark to `.build/widget-renders/` for a look. In the iOS 27.2 simulator the widget is offered in the gallery, draws
the snapshot on the Home Screen once Pesto has been active, a tile's in-place copy reaches the system clipboard
(`simctl pbpaste`, and a paste in Safari) and says Copied, and the show and open links open the detail and Safari; `xcrun simctl openurl` asks "Open in Pesto?" first, so answer it before reading the clipboard.

Sync on iOS is tested in `MobileSyncTests` against a Mac built as `SyncMac` (`Tests/PestoCoreTests/Sync`): the iPhone
side is a `MobileSync` on a `BookmarkedSyncFolder` with `FakeBookmarks` (counts every start and stop of the security
scope, and stages a stale link), a this-device key in `MemorySecrets` and a temp folder, never the Keychain or iCloud
Drive. A real iCloud Drive folder picked in the file picker, the sync key arriving through iCloud Keychain on a
device, file-presenter callbacks from the iCloud daemon and the app's return from the background are hand checks.

Pass 3 (ADR 0058) is covered in `CardCopyActionsTests` (Copy As JSON and Markdown, Decode JWT: what is offered, that it asks first, that Copy Payload closes it), `JWTDecodingTextTests` (Core), `GIFSharingTests`, `GIFSharingInTests` and the GIF cases of `SharedInboxTests` (a GIF beside a still is kept whole, one over the limit refused), `CardAIActionsTests` and `MobileAITests` (what is offered or greyed out and why; a fake model, never the real one), `AskPestoLibraryTests` (the chip, the rules by hand with the model off, the index narrowed to kinds and a day) and `SmartCollectionEditingTests` (every field makes a valid rule, Undo, a newer Pesto's rules kept). `Pass3UITests` (iPhone) drives Decode JWT with and without authentication (`PESTO_UITEST_JWT=1` adds a token; `PESTO_UITEST_DEFAULT_uitestAuthenticationGranted`), an AI action on the fixture model (`PESTO_UITEST_AI_FIXTURE=1`), the greyed-out menu with `PESTO_UITEST_DEFAULT_appleIntelligenceEnabled=false`, the Ask chip and a smart collection.

### iPhone and iPad: what only a device can check

Device-only checks are listed in `docs/ios-signing.md` ("What only a device can check"): iCloud Keychain key arrival, the Files picker against real iCloud Drive, Face ID and the App Switcher cover, a real screen recording or AirPlay, AutoFill from the system menu, the keyboard (below), the widget on a real Home Screen, the share sheet from real apps and the Action Button or Back Tap shortcut. Pass 3 adds, on a device with Apple Intelligence:
- an AI action on a long note (the answer says how much was read), Describe Image on a picture where the model can read pictures, and the same menu greyed out with the reason once Apple Intelligence is switched off in the iOS Settings app (Apple Intelligence & Siri) or in Pesto's own Apple Intelligence switch;
- Ask with the real model: type "pictures from last week" and choose Ask (then again with Apple Intelligence off: the rules answer);
- Decode JWT with Face ID, not the stub: a refusal opens nothing;
- share an animated GIF from Safari, Photos and Messages into Pesto and watch the card animate; share it back out to Messages and Files and check the receiver animates it.

### The keyboard on a device

On a signed device build, with a pinned clip, a snippet with a date placeholder and a few recent text clips in Pesto:
- **Add it**: Settings → General → Keyboard → Keyboards → Add New Keyboard → Pesto. Pesto is listed, Full Access off.
- **Without Full Access**: in Notes, switch to Pesto with the globe key. The numbers pad shows under one line on Full
  Access; no clip shows. Its keys type into the field.
- **Full Access on** (Keyboards → Pesto → Allow Full Access; read iOS's alert): with Insert from Pesto in other apps
  off, the line on turning it on; turned on in Pesto, the clips appear in Pinned, Snippets and Recent (the snippet
  shown with today's date), and a tap inserts the clip (the snippet expanded) and moves to your own keyboard. A long
  press inserts and stays, with a checkmark. Note which keyboard the tap lands on with three or more keyboards. A clip
  with a secret never appears.
- **Fresh set**: pin another clip in Pesto, switch back to the keyboard: it shows without restarting anything.
- **Chips and collections** (ADR 0062): in Pesto's iOS settings, under AutoFill and keyboard, open Collections and add two and reorder
  them: the keyboard's chips follow, after Recent, Pinned and Snippets. A clip copied on the Mac shows a laptop.
- **Word search**: in Notes type `basil`, switch to Pesto: a `"basil"` chip leads and only matches show; pick one:
  `basil` is replaced by the clip. Type `zzq`: the chip dims and the clips show unfiltered; × drops it. With the caret
  inside a word, no chip. Repeat the replace in a Safari web page's text field (each Delete must remove one
  character there too), and with "Stay in Pesto" tap a second match: the first clip is not touched.
- **Search page** (ADR 0063): tap the magnifying glass: the field, a row of clips and the letters show and the keyboard
  grows; type `bas`: the row narrows and nothing appears in the app's field; 123 types digits into the search; pick a
  clip: it is inserted and the page closes; Done closes it without inserting.
- **Layouts and keys** (ADR 0066): with English and Hebrew keyboards added in iOS Settings, the language key names the
  layout and holding space switches to Hebrew (Delete at the end of the top row); a held key shows its callout, a longer
  hold on `e` offers é, and sliding picks one; Shift once, a double tap locks caps. Add Korean: ㅎ ㅏ ㄴ types 한 and
  Delete leaves 하. Add Japanese: the field says it needs the system keyboard. Compare the keys side by side with
  Apple's keyboard (height, gaps, the callout).
- **Return inserts** (ADR 0066): type `bas` in Notes and switch to Pesto: the first match is ringed and Return reads
  Insert; it replaces `bas`. Without a word, Return types a new line.
- **Settings inside the keyboard** (ADR 0074): the gear chip at the end of the chips (no word) opens them; Small,
  Medium and Large resize the keyboard while your cards preview the size, two rows at Medium and Large upright; the
  Large preview fits without clipping the header; the ↗ button opens Pesto at Keyboard & AutoFill. Pesto's own
  Keyboard & AutoFill page shows the same preview framed as the keyboard and follows the size picker. The AutoFill
  picker has no gear (ADR 0073).
- **Cards like the app's** (ADR 0074): with sync on and clips from the Mac, keyboard, AutoFill and widget cards lead
  their foot line with the app's icon and glow faintly in its color, light and dark; Increase Contrast turns the glow
  off; a tinted or clear Home Screen and the Mac's desktop widget show no glow or icon.
- **Language key** (ADR 0074): with English and Hebrew keyboards, the search page shows EN beside 123; a tap shows HE
  and Hebrew letters; with one keyboard there is no key. Holding space still switches.
- **Scrolling the row** (with 20 or more clips, some pictures): fling the cards left, and while they still glide fling
  them back; start some drags slowly on a card, some near the screen's edges. Pass: the row always follows the finger
  at once, no card inserts during a drag, a tap still inserts and a hold still does the other insert. With "Stay in
  Pesto", insert a clip: the row stays where it was (it used to jump back to the first card).

### Widget pages on a device (ADR 0067)
- Add a medium and a large Recent Clips widget: medium shows two cards side by side, large two by two, each near the
  card's shape; on iPad add the extra large one (two by four, no page buttons).
- Press the chevrons: the page turns within a second, the dots follow, the last page wraps to the first. Press a dozen
  times in a minute and note whether a press ever stops turning the page (the reload budget).
- Copy something new on the Mac or in Pesto: the widget goes back to the first page; leave one on page two for ten
  minutes: it goes back by itself. Tinted and clear Home Screen modes: the controls take the tint and stay legible.
- **After inserting**: with "Stay in Pesto" chosen, a tap stays and a long press returns; the default is the reverse.
- **Bottom row**: Space, Return and Delete act in the field, Space and Delete repeat while held, 123 opens the pad and
  its other face brings the clips back. The globe key
  shows on a device without a system switch key; a tap moves to the next keyboard, a long press lists them.
- **History Lock**: turn it on in Pesto and let it lock: the keyboard says "No text clips yet." With "Show clips in widgets,
  AutoFill and the keyboard while locked" on, the clips come back.
- **Clear History** empties the set; turning off Insert from Pesto in other apps shows the line on turning it on.
- **No paste prompt**: in all of the above, iOS never asks to allow a paste from Pesto.
- **Memory**: run `PestoKeyboard` from Xcode attached to Notes and watch the memory gauge while the full set shows and
  the pad opens and closes: it stays well under the keyboard extension limit, and drops after the keyboard is hidden.
- **Lock Screen widgets** (ADR 0065): add circular, rectangular, and inline Pesto widgets on the Lock Screen; verify they show "Hidden on Lock Screen" by default with zero clip data exposed, turn on **Show Clips on Lock Screen** in Edit Widget to show the latest non-secret clip (secrets never appear), verify History Lock hides clips unless allowed, and verify opening prompts Face ID/passcode and opens the clip in Pesto.
- **iPad**: the cards in three columns, and the same states with a hardware keyboard attached.

## Lessons from the test suite

- **A run that prints nothing may be stuck, not slow.** `swift test` with its output in a file looks the same either
  way. Run it through `scripts/swift-test-watched.sh <log> <silent seconds>`: it stops a run whose log has been silent
  that long and lists the tests that started and never finished. The whole Core run takes under a minute, so three
  minutes of silence is a stall. To see where a stuck run waits, `sample <pid of swiftpm-testing-helper> 2`.
- **A blocking framework call on Swift's thread pool can stop the whole run.** Text recognition did: every pool thread
  waited inside Vision and no test ran again (`OCRThreadingTests`, `Sources/Core/Pasteboard/CLAUDE.md`).

- **A longer line of text in the setup window can fail the accessibility audit on a label you did not touch** (2026-10-16): the audit samples pixels at each element's frame, and a callout that wrapped to two lines moved the encryption-key label to a position it flagged, as a two-line toggle caption did on the last step. After any copy change in `OnboardingView`, run `test_onboardingSteps_passTheAccessibilityAudit`.

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
- **A timing assertion must not measure the main thread** (2026-11-26). In a full `swift test` run some suite holds the
  main thread for about 12 s, so a `@MainActor` test that times a 120 ms wait failed one run in two. Time it from a
  `nonisolated` test, and keep a wait that polls off the main actor (`FocusRestoration.waitForKeyboardFocus`).
- **Wait for a condition, not a duration.** `HistoryStore.waitForRefresh()` counts the saves posted for its history
  and returns once each has been handled and no refresh is pending; a fixed 150 ms sleep failed about one full run in
  sixteen.
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
