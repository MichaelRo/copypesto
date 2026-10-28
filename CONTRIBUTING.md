# Contributing to Pesto

Thanks for your interest in contributing. This guide covers everything you need to go from zero to an open pull request.

## Before you start

1. **Look at the open issues and discussions** to avoid duplicate work.
2. **Open an issue or start a [GitHub Discussion](https://github.com/MichaelRo/copypesto/discussions) first** for anything that changes what a person sees or does: a new feature, a new setting, a layout
   change. Say what problem it solves; a sketch helps. Pesto is deliberately small and private, so some good ideas
   will not fit (for example, anything that sends clip content off the Mac). A pull request for a UI change without an
   issue or prior discussion may be closed.
3. **Small fixes need no issue:** a bug with a failing test, a typo, a wrong caption.
4. **Read [AGENTS.md](AGENTS.md)** once. It is the working agreement for people and tools alike: module boundaries,
   conventions and the security invariants.

## Dev setup

**Requirements:** macOS 15+ and the full Xcode, not only the Command Line Tools: they cannot build `PestoCore`. Xcode 27
(the macOS 27 SDK) builds everything. Xcode 26 builds Pesto without Describe Image and picture screening, which compile
only with the macOS 27 SDK. Check `xcode-select -p`; if it points at `/Library/Developer/CommandLineTools`,
run `sudo xcode-select -s /Applications/Xcode.app` or export `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
(the Makefile and the git hooks honor it).

**Fix a Core bug in five minutes:** you need only Xcode and `swiftformat`/`swiftlint`. `make test-core` runs the
Core tests with no project and no signing. Everything below `make setup-signing` is for running the app.

```bash
git clone https://github.com/MichaelRo/copypesto.git
cd copypesto
export PATH="$(scripts/install-tools.sh):$PATH"   # the pinned xcodegen, swiftformat and swiftlint (a newer one can format differently)
git config core.hooksPath .githooks           # pre-commit lint and Core tests, pre-push checks
make setup-signing  # once, only to run the app: see "What make setup-signing changes" below
make build          # generates Pesto.xcodeproj and builds; needs no certificate (make run does)
make test-core      # fast SPM unit tests, no Xcode project required
make test           # full integration tests via xcodebuild
```

Run `make help` to see all available targets.

### What `make setup-signing` changes
It runs `scripts/setup-signing.sh`, which prints this and waits five seconds before it starts. In your login keychain it
creates a self-signed certificate named "Pesto Development" (a code-signing certificate, not a certificate authority) valid
for ten years, trusts it for code signing only (macOS asks for your password in a Certificate Trust Settings dialog), and
lets `codesign` use that one key without asking each time (`set-key-partition-list`, matched by the key's label; your other
keys are not touched, and if the label does not match, the first `codesign` asks once: choose Always Allow).
`PESTO_SIGNING_WIDE=1 make setup-signing` lets `codesign` use every signing key in the keychain without asking, as the first
version did. If a "Pesto Development" certificate is already there it does nothing; if one is there but not valid, it
tells you to delete it first, because a second would make `codesign` ambiguous. To undo it, delete the certificate in
Keychain Access. A new certificate resets the Accessibility grant and the Keychain entry an older one had earned. You do
not need it for `make test-core`, `make lint`, `make test` or the Core tests.

### A development build is the shipped app
A build made by `make run` or `make install` uses the same bundle identifier, preferences, store and Keychain key as an
installed Pesto, and `make run` quits the Pesto that is open. It refuses to quit one that is not a development build
(`PESTO_REPLACE=1 make run` overrides that). If you also use Pesto for real, back up first or work on another Mac or
user account. A development build never checks the official update feed. The first run of a changed build can ask for
your Keychain password again; "Always Allow" lets that build alone read the key.

### The tests
`make test-core` and `make test` write a few real Keychain items under unique names and remove them again; an unsigned
test process may ask for your login password once. The UI tests and `scripts/verify.sh` (about an hour, they drive
real windows and need system settings changed with `sudo`: see `docs/testing.md`) are the maintainers' gate. You do not
need to run them to open a pull request.

Open `Pesto.xcodeproj` in Xcode for UI work or interactive debugging.

## Branch naming

| Type | Pattern | Example |
|---|---|---|
| Feature | `feat/<short-description>` | `feat/stack-paste-buffer` |
| Bug fix | `fix/<short-description>` | `fix/jpeg-ingest-fallthrough` |
| Refactor | `refactor/<short-description>` | `refactor/extract-blob-cache` |
| Docs | `docs/<short-description>` | `docs/update-adr-0005` |
| Tests | `test/<short-description>` | `test/snapshot-rtl-variant` |

## Commit format

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary in imperative mood>

Optional longer body. Explain WHY, not WHAT.
```

**Types:** `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `perf`, `ci`  
**Scopes** (optional): `shelf`, `watcher`, `storage`, `paste`, `settings`, `backup`, `ci`

Examples:
```
feat(shelf): full-bleed picture cards with a gradient
fix(watcher): add public.jpeg and public.heic to priority list
test(snapshots): add RTL and focused card baselines
```

## PR checklist

Before opening a pull request:

- [ ] `make lint` passes (swiftformat + swiftlint --strict).
- [ ] `make test-core` passes, and `make test` for a change to `Features/` or `App/`. The maintainers run the full gate
  (`scripts/verify.sh`) before a merge.
- [ ] New `Core/` behavior has a failing test written first (TDD).
- [ ] A new or changed `Features/` view has a UI test (`docs/testing.md`). Snapshot tests are not part of the gate yet.
- [ ] A non-obvious pitfall you found is written in the `CLAUDE.md` note of the subsystem it belongs to.
- [ ] If the change touches a system-level area (paste flow, encryption, exclusion rules), a new or updated ADR exists in `decisions/`.
- [ ] The PR description explains the *why*, not just the *what*.
- [ ] The PR has a Summary and a Verification section (what you ran and what it showed). Pull requests are
  squash-merged under the PR title, so give it a Conventional Commits subject; keep each commit one logical change.

## Rules that fail a test

Most conventions are enforced by a test, so `make test-core` tells you. The ones people meet first:

| Rule | Test that fails | Read |
|---|---|---|
| Every Swift file starts with `// SPDX-License-Identifier: MIT` | `LicenseHeaderTests` | AGENTS.md |
| A preference is a `Setting` key, never a string literal | `SettingsRegistryTests` | AGENTS.md |
| UI text is American English; menu items Title Case, labels sentence case | `VocabularyTests` | [docs/copy-guide.md](docs/copy-guide.md) |
| `Core/` never imports SwiftUI, and its directories form a one-way graph | `ModuleBoundaryTests`, `CoreDirectoryCycleTests` | AGENTS.md, ADR 0007 |
| A new setting row is in `SettingsIndex` | `SettingsIndexDriftTests` | AGENTS.md |
| A count in a sentence has a plural entry in `Localizable.xcstrings` | `VocabularyTests` | AGENTS.md |
| Animations go through `Motion.animation`; colors through `pestoAccent` | `MotionRoutingTests`, `AccentUsageTests` | AGENTS.md |
| No new network host or analytics SDK | `NetworkGuardTests` (hosts); `ModuleBoundaryTests` and the pre-push hook (analytics) | AGENTS.md |
| No home path or personal email in a tracked file | `PersonalDataTests` | |

After adding a Swift file, run `make generate` so the Xcode project sees it.

## AI-assisted contributions

AI tools are welcome, and the maintainers use them too. Low-quality generated code is not: it will be closed.

- **Say so in the pull request description** when a tool wrote a meaningful part of the change.
- **You are responsible for the change.** Read every line, run the checks above, and be able to explain why it is right.
- **The license still applies:** only submit code you may release under the MIT license (see below), and keep the
  description short and the comments few, as in the rest of the code.
- No clip content, secret or personal data goes into a prompt, a test fixture or a screenshot.

## Security invariants

Never weaken these. Tests catch most violations; the list with the reasons is under "Security invariants" in
[AGENTS.md](AGENTS.md): no clip content goes to an AI service or to any host outside the short, enforced list in `AGENTS.md`, no third-party analytics SDK, clip data encrypted at rest,
exclusions for password managers that only a timed, per-app allowance can pass, secrets masked on the shelf, and AI
only on the device.

## Forks and your own builds

The code is MIT, so you are welcome to fork it. A build that you distribute needs its own identity, otherwise it could
be mistaken for the official app, or receive the official updates. Change the app name and icon, the bundle identifier
(`net.copypesto.pesto`), the update feed (`SUFeedURL`), the Sparkle key pair (`SUPublicEDKey`; make yours with
`generate_keys`), and your signing identity. See [TRADEMARKS.md](TRADEMARKS.md) for the name and icon.

## Licensing your contribution

By opening a pull request you agree that your contribution is released under the project's MIT license. New source
files start with the `// SPDX-License-Identifier: MIT` header.

## Reporting a security problem

Do not open a public issue. See [SECURITY.md](SECURITY.md).

## Questions?

For a design question, start a [GitHub Discussion](https://github.com/MichaelRo/copypesto/discussions) (or email
hello@copypesto.net if you would rather not post it). More ways to get help are in [SUPPORT.md](SUPPORT.md).

Issue labels you will see: `bug` and `enhancement`; the maintainers add others when a triage needs them.
