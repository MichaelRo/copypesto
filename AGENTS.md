# Pesto — Working Agreement

Read this whole file before touching any code. It records the project's conventions, invariants and the few non-obvious
patterns that recur across the codebase. Subsystem notes are the `CLAUDE.md` files under `Sources/` (plain Markdown
that any tool can read): read the one in the subtree you work in. Decisions are in `decisions/`, contribution rules in
`CONTRIBUTING.md`, setup and architecture in `docs/development.md`, recipes in `.claude/skills/`.

If a change makes a line here untrue, fix the line in the same pull request, and update `README.md` and `docs/guide/` when you add,
change or remove something a person can see. An ADR carries `## Docs affected`. Retired terms append to `docs/retired-terms.txt`.

---

## What Pesto is

A native macOS clipboard manager. Menu-bar utility + global hotkey (`⌘⇧V`) opens a bottom shelf of recent clips as a horizontal grid. History is local to the Mac in v1. One encrypted backup file per Mac in a chosen folder (iCloud Drive suggested; set up in Settings → Data, off until then, kept up to date automatically unless turned off) and restore from any backup file are built; multi-device sync is designed, not built (`decisions/0010-backup.md`). Distribution: unsigned (self-signed) at 1.0; Developer ID notarized once the Apple account exists — **not** Mac App Store, so no sandboxing.

Target platform: macOS 15+. Bundle ID: `net.copypesto.pesto` (was `io.pesto.app`; `LegacyIdentityMigration` moves an old install). Website and Sparkle feed: `copypesto.net`.

---

## Tech stack

Swift 6 (strict concurrency), SwiftUI for views, AppKit for system hooks (`NSPanel`, `NSPasteboard`, `NSWorkspace`,
`CGEvent`, Carbon hotkeys), SwiftData for the local store, CryptoKit for encryption, Sparkle for updates and
`swift-snapshot-testing` for snapshots. The table is in `docs/development.md`.

No third-party analytics or telemetry. Ever. This is a hard invariant.

---

## Module boundaries

**Rules enforced by tests (and `swiftlint` custom rules):**
- `Core/` must not `import SwiftUI`.
- `Features/` may import `Core/` but not vice versa.
- `Shared/` may not import either `Core/` or `Features/`.
- Inside `Core/`, the directories form a one-way graph (`CoreDirectoryCycleTests`, ADR 0005; its `allowedEdges` list is the exact graph): `Model` imports nothing; `Runtime`, `Imaging` and `Predicate` only `Model`; `Crypto`, `Backup`, `AI` (on `Imaging`) and `Intelligence` (on `Predicate`) sit on those; `Sync` on `Crypto`; `Pasteboard`, `Search` and `Storage` above them; `Import`, `Security` and `Paste` above `Storage`; `Seeding` on `Pasteboard`. A type that a lower directory needs moves down or behind a protocol (`AutomationHost`); the allowed-edge list may shrink and never grow.

When in doubt: if a function/type touches a SwiftUI `View`, it's in `Features/`. If it touches `NSPasteboard` or SwiftData models, it's in `Core/`.

---

## Coding conventions

**Naming**
- Types: `UpperCamelCase`, no prefixes (no `PE...` Pesto prefix — Swift modules handle namespacing).
- Properties / functions: `lowerCamelCase`.
- Acronyms in identifiers stay capitalized: `URLMetadata`, `HTTPResponse` when at the start of a type name.
- Test names carry explicit "when/then" scaffolding: `func test_whenXHappens_thenY()` in XCTest; in Swift Testing the `@Test("…")` text is a sentence, and the function is named `whenX_thenY()`.

**File structure**
- One primary type per file, and the filename is that type's name. A file of a few small related types (at most four, a `ShelfActions.swift` of its helpers) is named for the feature. More than four is split: `OneTypePerFileTests` fails on a new one, and the list of files that still need it may only shrink.
- File headers: the `// SPDX-License-Identifier: MIT` line and nothing else. No `// Created by ...` blocks; Git tracks authorship.
- Imports grouped: stdlib first, Apple frameworks next, third-party last. Sort alphabetically within each group.

**Comments — write almost none**
- Self-documenting code via good names. If you reach for a comment, first try renaming or extracting.
- **Do** write for: non-obvious invariants, race condition explanations, workarounds with Apple radar references.
- **Don't** write: what the code does, who wrote it, what task it relates to, aspirational TODOs without a tracked issue.

**Error handling**
- Never `try!`. `try?` only when nil is a deliberate, documented signal. `try` with `do/catch` everywhere else.
- Logged errors use `os.Logger` per subsystem — never `print`.

**Concurrency**
- Default to actors for mutable shared state. New view-facing state is `@Observable` (`AppState` is, with `@ObservationIgnored` on what views must not track; the shelf's and the floating window's history is one `HistoryStore`, ADR 0007).
- All `Core/` types must be `Sendable`. Don't `@unchecked Sendable` your way out.
- Long-running work: `Task.detached` only when you need to escape the actor; prefer `Task { ... }` in actor context.

**Force unwraps** — banned in production code. Tests may use them.

---

## Performance budgets

| Metric | Budget |
|---|---|
| Overlay open → first paint | < 100 ms on M1 Air (also measured after a copy made while it was closed) |
| Grid scroll | 60 fps with 5,000 items: median frame 16.7 ms, p95 under 33 ms, no hitch over 100 ms (`make bench-scroll`) |
| Search keystroke over 5,000 clips | < 4 ms (a quarter of a frame) |
| Paste, key press → clip in the target app | < 300 ms for every kind (< 900 ms for a 5 MB text) |
| Copy → card on the shelf | < 200 ms for every kind (< 400 ms for a 5 MB text) |
| Memory steady-state | < 150 MB |
| Watcher CPU (idle/background tier) | < 0.5% average |

Hardware budgets (`OverlayPerformanceTests`, `IngestPipelinePerformanceTests`, `CopyLatencyPerformanceTests`, `PasteWritePerformanceTests`, `HoverCardPerformanceTests`, `BackupWritePerformanceTests`, `HistoryMemoryTests`, `LargeHistoryPerformanceTests`, `WatcherPerformanceTests`) assert on a developer Mac and only measure on CI, where shared runners are ~2x slower (`RunEnvironment.isCI`). Memory is measured by `scripts/check-memory-budget.sh` (a gate step), scrolling by `make bench-scroll`, and paste, copy, shelf open, hover and memory after long copies end to end by `make bench-latency` (a real target app, the real clipboard saved and restored; it fails over budget, but needs an unlocked Mac and Accessibility, so it is not part of the gate). Baselines, what each assertion catches and the review that set them are in `docs/perf/budgets-2026-10.md` and `docs/perf/review-2026-10-10.md`.

---

## Security invariants

These are non-negotiable. Tests enforce them; reviewers reject changes that weaken them.

1. **No third-party network endpoints.** Permitted: the Sparkle appcast host in `Info.plist` and the update download host named in the appcast (github.com releases, only after the person accepts an update), `LPMetadataProvider` and the bounded downloads beside it in `URLMetadataFetcher` (link previews, which also fetch the page's icon and picture, and the GIF a browser's Copy Image named, all switchable off, ADR 0005), and `maps.apple.com` plus the carrier tracking pages (links the user opens). `NetworkGuardTests` enforce the list, so a new endpoint means editing its allowlist. **No clip content goes to any AI service**: every AI feature (actions, Describe Image, picture screening, Ask Pesto) runs on Apple's on-device model, with greyed-out UI when it is unavailable (`decisions/0005-no-network-but-a-short-list-and-ai-on-the-device.md`). Background or automatic AI requests to the network are prohibited.
2. **All blob storage and previews (colors aside), titles, notes, tags and search vectors are encrypted at rest.** `ClipboardBlob.encryptedData`, `previewCiphertext`, the sealed metadata (ADR 0002) and the sealed search vector (ADR 0002) are AES-GCM-256 under a random per-install key held in the login Keychain: not synchronised, readable only by the signing identity that created it (`decisions/0002-clip-data-is-sealed-at-rest.md`; it is **not** Secure Enclave wrapped). Each is sealed with its item's id and field as associated data, so a ciphertext moved to another row does not open (`decisions/0002-clip-data-is-sealed-at-rest.md`). `OnDiskEncryptionTests` scans a real store for plaintext (small clips and ones large enough for an external file). **Documented exceptions, all in the privacy guide:** the masked previews of secrets and colors; `last-item.json`, the preview of the latest clip that holds no secret, owner-only, for the `pesto` CLI and AppleScript (cleared by the History Lock, a delete and a wipe). Pesto puts nothing into Spotlight (ADR 0002).
3. **Exclusion rules are append-only.** Removing a built-in bundle ID from `ExclusionRules.defaultExcludedBundleIDs` requires an ADR and reviewer approval. The one way past it is the person's own timed allowance (`ExclusionAllowances`, ADR 0004; 15 minutes to until-quit, chosen in the Allow menu), which expires by itself and clears at launch. While it runs, that app's concealed copies are kept too (password managers mark everything concealed), stored hidden as category `credential` and removed when that allowance ends, at the latest a day after the copy (ADR 0004); no other app's concealed copy ever passes. A hidden clip is read only with Show, which asks for Touch ID or the password unless the person authenticated within their chosen window (`AuthenticationGrace`, ADR 0003).
4. **Sensitive content (credit cards, API keys, JWTs, PII) is masked in the grid preview.** Only `sensitivityMaskedPreview` shown at rest; the real text shows only through the card's Show action (eye button or context menu; Quick Look is not offered on a hidden clip), behind Touch ID or the account password unless asked recently (`AuthenticationGrace`), asked inside the shelf so it stays open, and a Show stays until Hide, the shelf closing, the lock or a cover (ADR 0003); paste writes the real text. See `decisions/0003-secrets-are-masked-and-shown-on-request.md`.
5. **No analytics SDKs anywhere.** The pre-push hook (and the manual CI workflow) grep for known SDK names (`Sentry`, `Mixpanel`, `Amplitude`, `Bugsnag`, `Crashlytics`, `Firebase`, `Datadog`, `Segment`, `GoogleAnalytics`, `PostHog`, `Heap`; the same list is in `.githooks/pre-push`, `ci.yml` and `ModuleBoundaryTests`). Fails on match.
6. **Concealed pasteboard markers are dropped silently.** `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, `com.apple.is-sensitive`, etc. Every marker has a dedicated test.
7. **What Undo holds is sealed, in memory, and wiped with the history** (`decisions/0008-undo-keeps-sealed-snapshots-in-memory.md`). `UndoHistory` keeps at most 20 actions and 16 MB, as the clip's stored ciphertext and never as plaintext, and never writes to disk. Clear History, Clear Everything, the History Lock and quitting empty it; a clip that expires, a credential and a clip over 4 MB are never held (`UndoPolicy`). A new path that wipes history calls `undoHistory.clear()`.

---

## Recipes

**Adding a new pasteboard type** — the `pasteboard-type` skill (`.claude/skills/pasteboard-type/SKILL.md`). Fixed touch-points in a fixed order.

**Extending the smart-pinboard DSL** — the `smart-pinboard` skill (`.claude/skills/smart-pinboard/SKILL.md`). DSL is intentionally constrained — no raw `NSPredicate` format strings (injection + migration risk).

**Migrating from the Paste app** — see `decisions/0011-read-only-surfaces.md`. Settings → Data → Import and export → Import from Paste: `PasteLibraryReader` reads a copy of `Paste.db` read-only, `PasteMigrator` routes records through `StorageService.ingest` (must run in-app — the encryption key is bound to the app's code identity), never writes blobs directly.

---

## TDD discipline

Every `Core/` bug fix starts with a failing test that reproduces the bug. No exceptions.

For new features in `Core/`, write the test first. For `Features/` (views), a UI test or a snapshot test is the unit-test analogue — write it before tweaking the view to match.

---

## Investigating a bug

1. Existing tests document the expected behavior more reliably than comments: read the ones around the code first.
2. `git log --oneline -- <file>` on the suspect file; read the last 3–5 commit messages.
3. `decisions/`: if the bug is in a system-level area (paste flow, exclusion rules, encryption), a decision likely
   explains the original intent. If a fix changes behavior a decision specified, write a new decision that supersedes
   it; do not edit an accepted one.
4. The `CLAUDE.md` note of the subtree, then the code.

---

## Repo-wide pitfalls

These hold everywhere. **Subsystem-specific pitfalls live in that subtree's `CLAUDE.md`** (`Sources/Core/*`, `Features/Overlay`, `Features/Settings`) and load when you work there.

- **Identity strings come from `AppIdentity`** (`Sources/Core/Runtime/AppIdentity.swift`): log subsystem, Keychain service and accounts, support folder, notification names, Spotlight domain. A literal `"io.pesto.app…"` fails `AppIdentityTests`. Changing one after release strands existing users' data, Keychain key or permissions. The content-hash salt `io.pesto.content-hash.v1` is deliberately unchanged.
- IMPORTANT: **A test must never read, write or remove a real preferences domain** (`UserDefaults(suiteName:)` and `persistentDomain/setPersistentDomain/removePersistentDomain(forName:)` act on the machine-wide domain, so `"io.pesto.app"` or the bundle ID is the user's actual settings). Use `ThrowawayDefaults.make()` (`Tests/PestoCoreTests/Support`, copied in `Tests/PestoTests/Support`): it names the suite by a path in the temp folder, because a named suite leaves a plist in `~/Library/Preferences` even after `removePersistentDomain` (10,000+ of them piled up), and `TestDefaultsHygieneTests` fails on a direct `UserDefaults(suiteName:)` in a test. `LegacyIdentityMigration` takes the legacy domain as a parameter for this reason. A migration test once emptied a developer's real `io.pesto.app` preferences.
- IMPORTANT: **Never touch the user's real machine state directly — go through the runtime seams** (`Sources/Core/Runtime`). A hosted-test or `-UITestMode` launch must not read or write the user's preferences, clipboard, store, Keychain, Spotlight index or Accessibility grant, and lint enforces it: use `AppDefaults.store` (not `UserDefaults.standard`), `AppPasteboard.general` (not `NSPasteboard.general`; the `pesto` CLI is the exception), `AccessibilityAccess` (not `AXIsProcessTrusted`), `AppPaths.supportDirectory`, and host UI with `SafeHostingView(pesto:)` so `@AppStorage` follows the same store. New system integrations (hotkeys, updaters, global monitors) start only when `LaunchMode.current.usesSystemIntegrations`. The XCTest host is detected from `XCTestBundlePath`/`XCTestSessionIdentifier` because Xcode 27 leaves `XCTestConfigurationFilePath` empty.
- **A hand-made `NSWindow` that AppDelegate retains must set `isReleasedWhenClosed = false`.** The default (`true`) makes AppKit release it on close as well; the second release crashes in the next display cycle (`NSTouchBarFinderSetNeedsUpdateOnMain`, macOS 27). This, not the last-window-closed policy, was "closing Settings quits the app".
- **A `@Query` reads the environment above its own view.** Inject `.modelContainer` on an ancestor (the window controller), never on the view that declares the `@Query`; otherwise it silently returns nothing (the quick menu was always empty).
- **`NSPasteboard` is not `Sendable` and Pesto does not claim it is.** Readers that run anywhere use `AppPasteboard.reader` (`SystemPasteboard`, reads only); writers use `AppPasteboard.general` on the main actor. `RetroactiveConformanceTests` fails on a new `@retroactive @unchecked Sendable`.
- **`StorageService` is built with a `StorageEnvironment`** (`.live(...)` in the app, `.testing { … }` in a test), never patched afterwards: a new dependency is a field of the environment. **A card asks the shelf to act through `@Environment(\.cardActions)`**, one `CardActions` value built by the grid; an absent action hides its menu command.
- **Every pasteboard write Pesto makes for a paste goes through `AppState.writeToPasteboard` (`OwnWriteGate`)**, so the watcher never re-ingests it and never swallows the user's next copy. Writes that should be captured (AppleScript copy, the CopyToPesto intent, the AI-result Copy button) stay off the gate. **A write that carries a clip's or the live board's text starts with `AppState.beginWrite(on:protected:)`** (or `writeText(_:protected:)`), which keeps a secret `.currentHostOnly` and concealed; a bare `clearContents()` + `setString` put passwords on Universal Clipboard (plain-text hotkey, Paste as…, Merge, stacks). `PasteboardWriteSourcesTests` lists the few files allowed to clear directly.
- **Every SwiftUI animation goes through `Motion.animation(_:)`** (`.animation(Motion.animation(.easeOut), value:)`, `withAnimation(Motion.animation())`), which returns nil under Reduce Motion; `MotionRoutingTests` scans for bypasses. Panels slide only when `PanelMotion.slides` says so. No fixed font sizes below 10 pt (`TypographyTests`); use text styles.
- **Views draw with `@Environment(\.pestoAccent)`, never `Color.accentColor`.** `Color.accentColor` ignores `.tint` and stays system blue, so the brand green and the user's chosen accent never reached the focus ring, chips or selections until every use moved to the environment value (set by `SafeHostingView(pesto:)` and each root). The same goes for text buttons (`.buttonStyle(.pestoLink)`, never `.link`, which is system blue) and an `NSSlider` (`trackFillColor`). `AccentUsageTests` scans `Features/`, `Shared/` and `App/`.
- **Pesto cannot hide its windows from a screen capture.** `NSWindow.sharingType = .none` stopped working against ScreenCaptureKit on macOS 15.4 and macOS has no public "is the screen captured" signal, so never rely on it: cards are covered by `ContentCover` (a detected share with the setting on, or Hide Clip Contents by hand, ADR 0003).
- **A color that follows the theme goes through `Color.pestoAccent(stored:theme:)` and `AppTheme`** (ADR 0013), and a new theme or tint value is checked by `AppThemeTests` (accent at 4.5:1 and text at 7:1 on its own tinted ground, light and dark). A new window root reads `@AppStorage(Setting.appTheme)` as the existing roots do.
- **Liquid Glass is chrome, not content.** The shelf is one `ShelfBackground` glass surface; cards are material with adaptive borders; chips are `PestoChip`. Don't add `.glassEffect` to cards or put glass on glass. Appearance flows only through `NSApp.appearance`; never `.preferredColorScheme` at a root.
- **Popovers opened from a context menu must be attached to the card, not the menu button** (the menu closes and takes the popover with it). The shelf's hover card is not a popover at all: it is `HoverCardPanel`, one borderless, non-activating child window that never becomes key (ADR 0009). A transient popover swallowed the click that dismissed it (P-59), and an `NSPopover` cannot be arrowless, clamped or hoverable. It is card material, not glass, takes the pointer only when its body scrolls, and shows `DetailFact`s (tested in Core) as one footer line; VoiceOver gets the same facts from the focused clip card (`voiceOverContent`), because focus never enters the panel.
- IMPORTANT: **Never register a `NotificationCenter` observer with `queue: .main` for a notification that the storage actor's context posts** (`ModelContext.didSave`, `NSManagedObjectContextDidSave`). The poster waits for the observer, so a save waits for the main thread while the main thread waits for that context: the app freezes with a burst of copies. Use `ModelSaveObserver`, which observes on the posting thread and hops to the main actor asynchronously.
- **AppKit text and image classes are not thread-safe** (`NSAttributedString` RTF/HTML import, `NSBitmapImageRep`): keep them `@MainActor`, tests included. Swift Testing runs tests in parallel, and `NSRTFReader` aborted a test process off the main thread.
- **A count in a sentence needs a plural entry in `Sources/Resources/Localizable.xcstrings`.** Use `CountText` or `String(localized: "\(count) clips …")` (the key is the sentence with `%lld`); an interpolation with no catalog entry prints "1 clips". Never `(s)` or a count ternary (`VocabularyTests`). A plural variation must print its number, or `xcodebuild` refuses the catalog; use positional specifiers (`%1$lld`) and say the number.
- **UI text is American English; menu items and buttons are Title Case, labels and captions sentence case** (`docs/copy-guide.md`). `VocabularyTests` scans `Features`, `App` and `CLI` for British spellings and off-vocabulary words. Every Swift file carries the SPDX line (`LicenseHeaderTests`). `make lint` ignores swiftformat's cache on purpose.
- **Hosted suites that touch a process-wide global nest under `HostedGlobals`** (`Tests/PestoTests/Support`): `.serialized` only orders tests inside one suite, and `AppDefaults.store`, `AppPasteboard.general`, `ScriptingContext`, `PreviewTextCache.shared`, `Announcer.speak` and `Motion` are shared by all of them. A test must restore what it sets (a struct suite cannot `deinit`: use a class).
- **`scripts/verify.sh` judges what ran** (`verify_judge.py`: floors on test counts, skips only if named in `verify-allowed-skips.txt`) and refuses to start while a Pesto is running. Run it once per batch. SwiftPM and `make` need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the Command Line Tools toolchain cannot build `PestoCore`.
- **A scan test gets its files from `SourceTree`** (`Tests/PestoRegressionTests/Support`), which throws on a missing folder or too few files. Never enumerate with `?? []`.
- **A covered card (screen-share blur, or sensitive and not shown) offers no side door**: `CardConcealment` switches off the hover popover, Quick Look, AI actions and drag. New ways of showing or handing out a clip's content go through it. Covered is not locked: Return, ⌘1–9 and a click paste a hidden card without showing it (ADR 0003), and Show is a deliberate act (the button on the blur, the menu, ⌘K, the VoiceOver action).
- **`AppState.writeItem` returns nil when it writes nothing** (locked, or a blob that will not open). A caller must stop the paste; the preview is never a fallback.
- **A preference is a `Setting` key, never a string literal** (`Sources/Core/Runtime/Setting.swift`, ADR 0012; `SettingsRegistryTests` scans): `@AppStorage(Setting.x)` in a view, `AppDefaults.store.value(for: Setting.x)` elsewhere, so a default is spelled once. A new key is also added to `Setting.allNames`. **A view reaches app logic through `AppState`** (closures the delegate sets, like `pasteInPlace`), never `AppDelegate` or `ScriptingContext` (`ModuleBoundaryTests`; only the two intents may).
- **`AppDelegate`, `ClipboardCard` and `GridView` are split into `+Something.swift` extension files** (status menu, settings window, paste flow; card parts, context menu, drag, loading; actions, selection bar) to stay under SwiftLint's length limits: put new logic in the matching extension, and relax `private` on a property an extension needs rather than growing the main file. What a tap, a paste, a merge or a stack does is decided in `Core/Paste/ShelfActions.swift`, where `ShelfActionsTests` can reach it.
- **A global shortcut is a case of `GlobalShortcut`** (Core), never a pair of `Setting` keys read by hand: its label, keys, default and Carbon id live there, and `HotkeyController`, the recorder, the status menu and the settings export read it. Stored, a modifier mask of 0 means "never changed" (the default, or none for the three that start unset) and `GlobalShortcut.disabledMarker` (-1) means turned off; the key code is not tested because 0 is the A key. A recorder asks `SystemShortcuts` (macOS's own list) before it accepts a combination.
- **A searchable setting is an entry in `SettingsIndex` and a `.settingsRow("<entry title>")` on its row** (`SettingsIndexDriftTests` fails on either missing); a pane's form carries `.settingsRowScrolling()`. A new indexed row that is a header or sits in a `Form` needs nothing else. A multi-line string literal in a view needs its closing `"""` on a line that ends with it, or `VocabularyTests` misreads the rest of the file.
- **New motion uses the four names in `Motion.swift`** (`pestoQuick`, `pestoMove`, `pestoWash`, `pestoPop`) through `Motion.animation`; a UI-test launch turns motion off (`-UITestMotion` turns it on). Menu-bar state changes have no animation on purpose.
- **A UI test cannot press a real system shortcut**: macOS takes it first (⌘⇧3 took screenshots of the developer's desktop). Test the combination logic in Core (`SystemShortcutsTests`).
- **A change a person makes to a clip or collection is recorded for Undo where it is made** (ADR 0008): a clip edit goes through `ClipEditor`, a collection change through `CollectionStore`, an add, a delete or a pin through `StorageService`. A view never edits a model and calls `try? save()`: the change would be saved but not undoable, and a failure would be silent. A view reaches them through `appState.clipEditor(context:)`, `appState.collectionStore(context:)` and `appState.storageService`, never a second `StorageService(modelContainer:)`, which has its own empty history.
- **A click on a shelf card only focuses it; a double click pastes** (`ShelfTap.route`, ADR 0009), and Delete removes the whole selection after an in-shelf confirmation. UI tests double-click to paste. A stack pastes one clip per plain ⌘V through a global monitor that exists only with Accessibility and `usesSystemIntegrations` (ADR 0009).
- **One authentication window** (`AuthenticationGrace`, ADR 0003): the History Lock and every protected action share one "Ask for Touch ID again after" setting. Do not reintroduce a second timer.
- **A bare hex string is a color only with a letter A–F and a digit** (ADR 0002): color previews are the one unencrypted preview, so a number or a word (`decade`) classified as a color would sit in the store in the clear. `#` and three differing digits (`#178`, `#404`) is a reference number, not a color. `rgb()`, `rgba()`, `hsl()` and `hsla()` count only when `ColorLiteralParser.isFunctionalColor` reads the whole text (`rgb(password=…)` is text), and whatever filed a clip as a color, `ColorPreviewPolicy` judges the preview again before it is stored in the clear; storage code never compares with `.color` itself (`ColorClearTextGateTests`).
- **An importer reads a copy, read-only, with bounds, then goes through `PasteMigrator`** (ADR 0011); never write a clip around `StorageService.ingest`.
- **A new Swift file needs `make generate`** before `xcodebuild` sees it (the project is generated), and every new file carries the SPDX line first: `swiftformat` can move an `@testable import` above it.
- **Sync is off in v1** (`SyncAvailability.isAvailable == false`, handoff `docs/sync-design.md`). Do not start CloudKit or show "Connected".
- IMPORTANT: **Every `NSHostingView` must be `SafeHostingView`.** Any raw `NSHostingView` in any visible panel will crash with `EXC_BREAKPOINT` at `_postWindowNeedsUpdateConstraints` on macOS 26. Run `grep -rn "NSHostingView" Sources/` before every commit that adds a new window or panel. (Enforced by a PostToolUse hook in `.claude/settings.json`.)
- IMPORTANT: **Never write `NSApp.delegate as? AppDelegate` (or `NSApplication.shared.delegate as?`) anywhere.** SwiftUI wraps the delegate, so the cast is always nil and the code silently does nothing: the card context menu's Copy, the floating window's tap-to-paste and the Shortcuts "Paste from Pesto" action were all dead this way. Reach app logic through `AppState` (closures the delegate sets, like `openSettingsFromOverlay`) or `ScriptingContext`. `DelegateCastTests` scans for it.
- **AppleScript in SwiftUI `@NSApplicationDelegateAdaptor` apps requires three things:** (a) `NSAppleScriptEnabled = true` in `Info.plist` (not just `OSAScriptingDefinition`) — without it the scripting infrastructure never loads; (b) sdef command codes must be exactly 8 chars (4-char class + 4-char event ID); (c) `NSApp.delegate as? AppDelegate` always returns `nil` — use a `ScriptingContext` static enum with `nonisolated(unsafe)` properties populated at `bootStorage()` time as the bridge from `NSScriptCommand` subclasses to app state.
- **A development build is the shipped app** (same bundle ID, Keychain key, preferences, store). `make` targets that delete that state (`reset-onboarding`, `reset-dev-state`) need `PESTO_DEV_RESET=1`; `DevToolingSafetyTests` fails on a destructive target without `require-dev-reset`. Never run them on someone else's Mac without asking.
- **The app icon is Basil, drawn by `design/source/brand-art.py` and `icon-layers.swift`; never set a Finder icon on the installed app.** `NSWorkspace.setIcon` writes Finder metadata into the signed bundle and `codesign --verify --strict` then fails (ADR 0013). The icon choice only sets `NSApp.applicationIconImage`.
- **`make setup-signing` is mandatory for development.** Without the "Pesto Development" code-signing cert, every `make run` produces a binary with a different CDHash → macOS treats it as a new app → the TCC database invalidates the Accessibility grant AND the Keychain's "Always Allow" entry. `make run` hard-fails (via `make check-signing`) when the cert is missing. `scripts/setup-signing.sh` (the target) creates a self-signed leaf code-signing cert, trusts it for code signing only, and runs `security set-key-partition-list` for that one key by label (`PESTO_SIGNING_WIDE=1` widens it to every signing key); it prints what it changes first, and `SigningRecipeTests` pins it. It cannot be run on a build machine, so a change to it needs a hand check on a spare user account.
- **`NSApp.appearance` is the only reliable way to drive light/dark across all panels and reset to system, but it can also reach the menu bar's status window.** Skip that window when theming windows. The menu bar's colour follows the wallpaper, not the Mac's Light or Dark setting (a Dark Mac can have a light bar): `applyStatusItemAppearance` asks the status window what the bar looks like with and without the app's appearance forced and pins the button only if they differ, and then to the bar's own answer, never to the Mac's setting (`MenuBarAppearance`, ADR 0013). SwiftUI `.preferredColorScheme` is one-way: it sets but does not clear. Switching from System → Light → System leaves windows stuck on `.aqua` unless you explicitly set `NSApp.appearance = nil` and null out each `window.appearance`. Drive theming via a `UserDefaults.didChangeNotification` observer in `AppDelegate` that calls `applyAppearance()`.
- **No feature gating.** Pesto ships every feature free on every install, and donations (GitHub Sponsors) unlock nothing in the app (ADR 0001; no StoreKit). Do not add a tier, flag or gate that disables functionality.
- **`\.accessibilityReduceTransparency` (and other system-state accessibility environment values) is a read-only `KeyPath`, not `WritableKeyPath` — it cannot be injected via `.environment(\.accessibilityReduceTransparency, true)` in tests/previews.** It reads live system state directly; the call site fails with "cannot convert `any KeyPath<EnvironmentValues, Bool> & Sendable` to `WritableKeyPath<...>`". To make a view depending on it testable, define your own writable override key (`Bool?`, default `nil`) that the view composes with the real value (`override ?? systemValue`); tests set the override, production code never does. See `Sources/Shared/Extensions/AdaptiveMaterial.swift` (`reduceTransparencyOverride`) for the pattern.

---

## Running the project

**`swift test` prints two "Test run with" lines** (the regression target, then Core); `tail -1` hides a failure, so read three lines or let `scripts/verify_judge.py` judge. An `xcodebuild` without the `test` action only builds and exits 0.

**Run `scripts/verify.sh` (`make verify`, about 40 minutes with the UI tests) before claiming any task done and paste its summary.** Start it in the background and read only `SUMMARY.txt` and `failures.txt` in its log folder; re-run just the failed tests with `scripts/verify-rerun-failed.sh` (`docs/testing.md`, "Running the gate cheaply"). It runs lint, the Core tests, a Debug
build with warnings as errors, the hosted and UI tests, and exports screenshots of the real UI to
`.build/ui-screenshots/`; it exits non-zero on any failure (`--fast` skips the UI tests). Setup, how the UI-test mode
works, how to write a UI test and the manual checklist for what cannot be automated are in `docs/testing.md`.

Pre-commit checks run automatically via `.githooks/pre-commit`. If `xcode-select -p` points to CommandLineTools rather than Xcode, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
