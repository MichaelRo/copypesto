# 0024. Setup's last step offers "Launch Pesto at login" already on

Status: Accepted

Relates to [0001](0001-free-and-open-source-no-feature-gating.md) (one installed copy; login launch registers only an app in Applications) and [0012](0012-settings-and-shortcuts.md) (typed settings). Nothing about storage, sync or the network changes.

## Context
Pesto lives in the menu bar and only copies what it sees while it runs. Setup's last step offered "Launch Pesto at login" as a switch that started off, so a person who simply chose Get Started had a shelf that was gone after the next restart: no menu bar icon, no shortcut, and every copy until they opened Pesto again was missed. Clips already saved are never lost by a restart; the gap is what is copied while Pesto is not running. Whether macOS reopens an app that was open at logout ("Reopen windows when logging back in") was not tested, and Pesto must not rely on it.

## Decision
- **The switch opens on.** When the last setup step appears and the login item is off, `LoginItemSetupDefault.applyOnce` registers it once through `LoginItemService`. The switch shows the real state, the caption says what it does, and the person can turn it off there or later in Settings → General.
- **The offer is made once per Mac** (`Setting.loginItemOffered`, this Mac's own state, not carried by a backup). Whatever the person answers is kept: a Mac that was offered it, or has it off, is never turned on again by this.
- **A refusal is recorded too.** An app outside Applications cannot register; the switch shows macOS's explanation as before, and setup does not retry it.
- **Nothing changes for existing installs**, and nothing registers in a UI test or hosted test (their backend refuses).

## Consequences
- It is opt-out instead of opt-in. That is a deliberate trade: the switch is visible and one click from off, and a menu-bar tool that vanishes after a restart costs more than a login item some people do not want.
- A person who ignores the step gets a login item. The guide says so in the setup description.
- Setup's picture shows the switch off, because the UI-test backend refuses to register; the real step shows it on.
- The release hand check "Launch at login survives a reboot" still applies (`docs/testing.md`).

## Docs affected
- `docs/guide/getting-started.md` (the "Make it yours" step)
- `decisions/README.md` (this record in the table)
