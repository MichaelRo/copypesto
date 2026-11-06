# 0024. Setup's last step offers "Launch Pesto at login" already on

Status: Accepted

Relates to [0001](0001-free-and-open-source-no-feature-gating.md) (one installed copy; login launch registers only an app in Applications) and [0012](0012-settings-and-shortcuts.md) (typed settings). Nothing about storage, sync or the network changes.

## Context
Pesto lives in the menu bar and only copies what it sees while it runs. Setup's last step offered "Launch Pesto at login" as a switch that started off, so a person who simply chose Get Started had a shelf that was gone after the next restart: no menu bar icon, no shortcut, and every copy until they opened Pesto again was missed. Clips already saved are never lost by a restart; the gap is what is copied while Pesto is not running. Whether macOS reopens an app that was open at logout ("Reopen windows when logging back in") was not tested, and Pesto must not rely on it.

## Decision
- **The switch opens on.** When the last setup step appears and the login item is off, `LoginItemSetupDefault.applyOnce` registers it once through `LoginItemService`. The switch shows the real state, the caption says what it does, and the person can turn it off there or later in Settings → General.
- **It is offered once per Mac** (`Setting.loginItemOffered`, this Mac's own state, not carried by a backup), and only to a Mac that has not finished setup (`hasOnboarded` false). Whatever the person answers is kept: a Mac that was offered it, has it off, or finished setup before this existed is never turned on again by this, even if setup is shown again because the Keychain key is missing.
- **A refusal is recorded and shown.** An app outside Applications cannot register: the step shows macOS's explanation, as the Settings switch does, and setup does not retry it.
- **Nothing registers in a UI test or hosted test**: `applyOnce` does nothing unless the launch uses system integrations, so those setup screens show no refusal either.

## Consequences
- It is opt-out instead of opt-in. That is a deliberate trade: the switch is visible and one click from off, and a menu-bar tool that vanishes after a restart costs more than a login item some people do not want.
- The login item is registered when the last step appears, not at Get Started, so a person who quits setup on that step has it (and macOS's "login item added" notice) without having finished. They can turn it off in Settings.
- A person who ignores the step gets a login item. The guide says so.
- Setup's picture shows the switch off, because the UI-test launch does not register; the real step shows it on.
- The release hand check "Launch at login survives a reboot" still applies (`docs/testing.md`).

## Docs affected
- `docs/guide/getting-started.md` (the "Make it yours" step)
- `decisions/README.md` (this record in the table)
