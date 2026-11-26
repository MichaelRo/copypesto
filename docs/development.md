# Developing Pesto

Everything a contributor needs: how the code is organized, how to build and test it, and the rules it holds itself to.
The user-facing overview is in the [README](../README.md); the system diagrams and module/security overview are in [architecture.md](architecture.md); the working agreement is [AGENTS.md](../AGENTS.md).

## Architecture

For detailed module dependency graphs, trust boundaries, capture/OCR/storage data flow, and sync/backup protocols, see [architecture.md](architecture.md).

```
Sources/
├── App/            — macOS entry point, AppDelegate, hotkey wiring, onboarding
├── Core/           — cross-platform business logic (no SwiftUI; macOS 15+ and iOS 26+)
│   ├── Model/        — value types everything shares; imports nothing else in Core
│   ├── Crypto/       — AES-GCM-256 blob encryption, HPKE SharedInbox, QuickInsert/Widget sealed files
│   ├── Imaging/      — bounded image decoding, SVG thumbnails
│   ├── Seeding/      — demo, marketing and benchmark histories
│   ├── Pasteboard/   — watcher, type detection, exclusion rules, sensitivity, OCR
│   ├── Storage/      — SwiftData models, ingest, retention, SyncFolderService, HistoryStore/Index
│   ├── Backup/       — chunked .pestobackup format, key store, automatic-backup policy
│   ├── Import/       — Paste/Alfred/CleanClip library readers, collection import, first-run samples
│   ├── Runtime/      — launch modes and the seams (defaults, pasteboard, paths) that keep tests off your machine
│   ├── Security/     — History Lock, authentication
│   ├── AI/           — on-device model access (Apple Intelligence only)
│   ├── Intelligence/, Search/ — suggestions and search by meaning
│   ├── Sync/         — encrypted append-only sync format, keys, 8-word pairing, high-water marks
│   ├── Paste/        — focus restoration, AX direct-write, CGEvent fallback
│   └── Predicate/    — smart-collection DSL
├── CoreNetworking/ — link previews & GIF fetching (PestoCoreNetworking; linked only by apps, never extensions)
├── Features/       — macOS SwiftUI views (may import Core, never the reverse); `Marketing/` draws doc pictures
├── Mobile/         — the iPhone and iPad app (target `PestoMobile`, ADR 0046); never compiled into the Mac app
├── MobileAutoFill/ — iOS AutoFill extension (`PestoAutoFill`, text insertion from `QuickInsertFile`, ADR 0051)
├── MobileKeyboard/ — optional iOS keyboard extension (`PestoKeyboard`, ADRs 0061–0064)
├── MobileShare/    — iOS share extension (`PestoShare`, HPKE-sealed `SharedInbox`, ADR 0047)
├── MobileShared/   — iOS card & layout views shared across `PestoMobile`, `PestoKeyboard`, and `PestoMobileTests`
├── MobileWidget/   — iOS WidgetKit extensions (`RecentClipsWidget`, `LockScreenClipsWidget`, `CopyClipIntent`, ADRs 0052, 0065)
├── Widget/         — shared Recent Clips widget views and `WidgetSnapshotReader` (`PestoWidget` + `PestoControls`)
├── CLI/            — the `pesto` command-line tool (`make build-cli`)
├── Controls/       — the macOS Control Center & WidgetKit extension (`PestoControls`, ADR 0059)
├── Resources/      — Info.plists, entitlements, asset catalogs, localization catalogs, AppleScript `.sdef`
└── Shared/         — extensions and utilities, compiled into the Mac app and the iOS targets
```

SwiftPM (`Package.swift`) exposes `PestoCore` (`Sources/Core`), `PestoCoreExtension` (extension-safe alias of `PestoCore` with zero network symbols), and `PestoCoreNetworking` (`Sources/CoreNetworking`). `PestoCore` is tested without a built app by `make test-core`, including the SwiftData storage layer (`Core/Storage/Models`). SwiftData's macros need Xcode's toolchain, which every supported build uses. `PestoCore` builds for macOS 15 and iOS 26 (ADR 0046): what only a Mac can run is inside `#if os(macOS)`, and `xcodebuild build -scheme PestoCore -destination 'generic/platform=iOS Simulator'` checks the iOS side. `PestoMobile` embeds `PestoShare`, `PestoAutoFill`, `PestoKeyboard`, and `PestoWidget`; `Pesto` embeds `PestoControls` (and compiles `Sources/Widget` when signed with both `SYNC_PROFILE` and `WIDGET_PROFILE`, ADR 0059). The hosted tests (`PestoTests`) are the ones that need the Mac app itself: its state, windows and launch. `AppDelegate`, `ClipboardCard` and `GridView` are split into `+Something.swift` extension files; preferences are typed `Setting` keys (ADR 0012); `AppState` is `@Observable` and the shelf's history is one `HistoryStore` (ADR 0007). The app build uses an `xcodegen`-generated project (`Pesto.yml`).

## Tech stack

| Layer | Choice |
|---|---|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI + AppKit (`NSPanel`, `NSPasteboard`, Carbon hotkeys) |
| Persistence | SwiftData (`@Model`, `@Attribute(.externalStorage)`) |
| Encryption | CryptoKit AES-GCM-256, per-install key in the login Keychain (this device only) |
| Snapshot tests | swift-snapshot-testing |
| Auto-update | Sparkle 2.x, pinned by commit in `Pesto.yml` with swift-snapshot-testing; `make check-packages` compares both pins with the latest releases and known advisories, because Dependabot cannot read `Pesto.yml` (a `make build`, `make run` or `make install` build never starts it, so *Check for Updates…* there says so in a toast) |

## Development

```bash
# Prerequisites
export PATH="$(scripts/install-tools.sh):$PATH"   # the pinned xcodegen, swiftformat and swiftlint

# One-time: create a stable signing cert so Accessibility + Keychain
# permissions persist across rebuilds (otherwise macOS re-prompts every
# `make run` because each unsigned binary has a different CDHash).
make setup-signing   # prints what it changes in your login keychain and waits 5 s; see CONTRIBUTING.md

# All common tasks are available via make — run this to see them:
make help

make generate   # Regenerate Pesto.xcodeproj from Pesto.yml
make build      # generate + xcodebuild debug build (no signing)
make run        # build + sign with stable cert + open Pesto.app
make test-core  # swift test on PestoCore — fast, no Xcode project needed
make test       # xcodebuild hosted tests (snapshot + UITests skipped)
make build-mobile  # the iPhone and iPad app, for the simulator
make test-mobile   # its tests on an iPhone and an iPad simulator (needs an iOS simulator runtime)
make build-mobile-device DEVICE="My iPhone"  # signed for a connected device (docs/ios-signing.md)
make test-mobile-ui  # its UI smoke tests, iPhone then iPad
make verify     # the full gate: lint, Core + hosted + UI tests, screenshots (docs/testing.md)
make lint       # swiftformat --lint + swiftlint --strict
make format     # auto-format all Swift sources
make clean      # remove .build/xcode

# Open in Xcode (for UI work or debugging)
open Pesto.xcodeproj
```

Git hooks (`pre-commit`, `pre-push`) run SwiftFormat, SwiftLint, and the Core test suite automatically. Install them:

```bash
git config core.hooksPath .githooks
make setup-merge-drivers   # String Catalogs merge entry by entry (see "Merging")
```

## CI

The gate is `scripts/verify.sh` (and the `.githooks/pre-push` hook). The GitHub Actions workflow runs the Linux analytics
check on every push and pull request; the macOS `verify` job runs on a pull request that changes code, tests, scripts or project files and whose base is `main`
(a stacked pull request runs it once retargeted; a docs-only one never), and by hand (Actions tab, CI, Run workflow), on the
Xcode 27 runner image. A green run leaves a marker keyed by the pull request's tree, so a rebase or re-run that changed no
file skips the twenty minutes and reports success. The branch ruleset does not require branches to be up to date, so a merge
never re-runs another pull request's check. There the card snapshots, text recognition and a few hardware budgets are skipped (named in
`scripts/verify-allowed-skips.txt`); `scripts/verify.sh` on a Mac runs all of them. Its jobs (actions pinned to commit SHAs, lint tools
pinned in `scripts/tool-versions.env`):

| Job | What it checks |
|---|---|
| `no-analytics` | Grep for forbidden SDK imports (Sentry, Firebase, etc.) |
| `verify` | `scripts/verify.sh --no-ui`: SwiftFormat + SwiftLint, every SPM test (Core and Regression), a Debug build with warnings as errors, and the hosted `PestoTests` |

The UI tests and snapshot tests drive real windows, so they run locally (`scripts/verify.sh`, `docs/testing.md`).

## Merging

`main`'s ruleset ("Branch protection") requires a pull request, the `verify` and `no-analytics` checks and **the merge
queue**. A skipped check reports success, so a pull request whose `verify` was skipped (it was stacked on another branch
when it ran) could land untested; in the queue, `verify` always runs, on the pull request merged with the newest `main`
(`merge_group`), and the pull request lands only if it passes. A pull request that already passed on that exact code
passes there in about a minute (the tree marker above). Press **Merge when ready** (or `gh pr merge --squash --auto`);
queue several at once, and the queue merges them one after another without asking you to update any branch.

Two files gain a little in nearly every pull request and conflicted on every merge (2026-11-25: five rounds):
`.gitattributes` keeps both sides' new rows of `decisions/README.md` (`merge=union`; the rows may land out of number
order, which a later edit can sort), and merges `*.xcstrings` entry by entry with `scripts/merge-xcstrings.py` once
`make setup-merge-drivers` has registered it in your clone. A string both sides changed differently is still a conflict
for a person. GitHub's own "This branch has conflicts" does not run custom drivers: merge `main` into the branch locally
(`git merge origin/main`), where they do, and push.

Prefer pull requests branched from `main`. A stack is fine for work that builds on work, but squash merging rewrites the
base's commits, so merge a stack bottom-up and merge `main` into the next branch at once.
Releasing is described in `docs/release.md`. Signing the iPhone and iPad app for a device, and what the developer portal needs, is in `docs/ios-signing.md`; the App Store listing, privacy answers and review notes are in `docs/app-store-ios.md`.

## Security invariants

The list, with the reasons, is under "Security invariants" in [AGENTS.md](../AGENTS.md); `decisions/` holds the ADRs
behind them. In short: no clip content goes to an AI service or to any host outside the short, enforced list in `AGENTS.md`, no analytics or third-party SDK, clip data encrypted at rest,
secrets masked on the shelf, built-in exclusions for password managers that only a timed per-app allowance can pass,
and AI only on the device.

## Project files

| File | Purpose |
|---|---|
| `AGENTS.md` | The working agreement for contributors and coding tools: conventions, pitfalls, security invariants. Subsystem notes live in `CLAUDE.md` files under `Sources/` (plain Markdown any tool can read) |
| `decisions/` | Architecture decision records |
| `docs/` | [architecture.md](architecture.md), the user guide (`guide/`), testing, release, performance budgets and design notes |
| `.claude/skills/` | Recipes for adding a pasteboard type or a smart-collection rule, and for keeping the notes true |
