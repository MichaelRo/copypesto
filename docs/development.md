# Developing Pesto

Everything a contributor needs: how the code is organized, how to build and test it, and the rules it holds itself to.
The user-facing overview is in the [README](../README.md); the working agreement is [AGENTS.md](../AGENTS.md).

## Architecture

```
Sources/
├── App/          — entry point, AppDelegate, hotkey wiring, onboarding
├── Core/         — business logic (no SwiftUI)
│   ├── Model/        — value types everything shares; imports nothing else in Core
│   ├── Crypto/       — AES-GCM-256 blob encryption, sealed files
│   ├── Imaging/      — bounded image decoding, SVG thumbnails
│   ├── Seeding/      — demo, marketing and benchmark histories
│   ├── Pasteboard/   — watcher, type detection, exclusion rules, sensitivity
│   ├── Storage/      — SwiftData models, ingest, retention, link previews, capture pipeline
│   ├── Backup/       — backup file format, key store, automatic-backup policy
│   ├── Import/       — Paste library reader, first-run samples
│   ├── Runtime/      — launch modes and the seams (defaults, pasteboard, paths) that keep tests off your machine
│   ├── Security/     — History Lock, authentication
│   ├── AI/           — on-device model access (Apple Intelligence only)
│   ├── Intelligence/, Search/ — suggestions and search by meaning
│   ├── Sync/         — device identity, sequence counter, `SyncAvailability` (sync is off)
│   ├── Paste/        — focus restoration, AX direct-write, CGEvent fallback
│   └── Predicate/    — smart-pinboard DSL
├── Features/     — SwiftUI views (may import Core, never the reverse); `Marketing/` draws the documentation pictures
├── CLI/          — the `pesto` command-line tool (`make build-cli`)
├── Controls/     — the Control Center extension
└── Shared/       — extensions and utilities
```

All of `Core/` is the SwiftPM module `PestoCore`, tested without a built app by `make test-core`, the storage layer
(`Core/Storage/Models` and `Migration`: the SwiftData models, ingest, delete, encrypt, restore) included. SwiftData's
macros need Xcode's toolchain, which every supported build uses. The hosted tests (`PestoTests`) are the ones that need
the app itself: its state, windows and launch. `AppDelegate`, `ClipboardCard` and `GridView` are split into `+Something.swift` extension files; preferences are typed `Setting` keys (ADR 0012); `AppState` is `@Observable` and the shelf's history is one `HistoryStore` (ADR 0007). The app build uses an `xcodegen`-generated project (`Pesto.yml`).

## Tech stack

| Layer | Choice |
|---|---|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI + AppKit (`NSPanel`, `NSPasteboard`, Carbon hotkeys) |
| Persistence | SwiftData (`@Model`, `@Attribute(.externalStorage)`) |
| Encryption | CryptoKit AES-GCM-256, per-install key in the login Keychain (this device only) |
| Snapshot tests | swift-snapshot-testing |
| Auto-update | Sparkle 2.x (a `make build`, `make run` or `make install` build never starts it, so *Check for Updates…* there says so in a toast) |

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
```

## CI

The gate is `scripts/verify.sh` (and the `.githooks/pre-push` hook). The GitHub Actions workflow runs the Linux analytics
check on every push and pull request; the macOS `verify` job runs by hand (Actions tab, CI, Run workflow) until a hosted run
passes, and the comment at the top of `.github/workflows/ci.yml` says how to turn it on for every change. Its jobs (actions pinned to commit SHAs, lint tools
pinned in `scripts/tool-versions.env`):

| Job | What it checks |
|---|---|
| `no-analytics` | Grep for forbidden SDK imports (Sentry, Firebase, etc.) |
| `verify` | `scripts/verify.sh --no-ui`: SwiftFormat + SwiftLint, every SPM test (Core and Regression), a Debug build with warnings as errors, and the hosted `PestoTests` |

The UI tests and snapshot tests drive real windows, so they run locally (`scripts/verify.sh`, `docs/testing.md`).
Releasing is described in `docs/release.md`.

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
| `docs/` | The user guide (`guide/`), testing, release, performance budgets and design notes |
| `.claude/skills/` | Recipes for adding a pasteboard type or a smart-collection rule, and for keeping the notes true |
