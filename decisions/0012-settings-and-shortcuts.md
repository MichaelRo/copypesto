# 0012. Settings are seven panes with search that goes to the row, typed keys with one default, and one list of global shortcuts

Status: Accepted

## Context
Settings grew from tabs to a sidebar through several regroupings. The failures were consistent: panes that mixed
unrelated controls, settings placed by implementation rather than by the topic a person would look under, rows that
repeated each other, and a search that opened a pane but left the person to hunt for the row.

Preferences were string literals in dozens of `@AppStorage` and `UserDefaults` calls, each repeating its default. A
background reader (`StorageService`, the hotkey controller) cannot use `@AppStorage`'s default, and a typo silently
created a second preference. AppKit strings (menus, alerts, window titles, accessibility labels, the error banner)
bypassed the String Catalog.

Global shortcuts were spelled in four places (registration, recorder, menu text, backup). A stored key code of zero
meant "never changed", which is also the A key, so recording ⇧⌘A registered ⇧⌘V. A registered Carbon hotkey is consumed
before any window sees the key, so recording the combination already in use opened the shelf, and a combination macOS
had claimed never fired.

## Decision
**Panes.** `SettingsView` is a `NavigationSplitView` with a hand-drawn sidebar of seven panes (`SettingsSection`):
General, Appearance, Privacy, Shortcuts, Collections, Snippets, Data. The system sidebar would paint selection in the
system accent, not Pesto's (ADR 0013). The window is at least 760 by 640 points (`SettingsWindowFrame`).
- Each pane is one grouped `Form` that opens with `SettingsPaneHeader` (tile, name, one sentence, the pane's main
  action). `settingsPaneTop` pins it on an opaque ground with a hairline. A header is not a `Form` section, and header
  text never takes `.fixedSize(vertical:)`: the minimum size is measured at zero width and the window would draw shifted
  under its title bar. Layout rules: `docs/design-language.md`.
- A setting lives in one place by topic, and a read-only row never repeats a toggle. Privacy opens with the promise (ADR
  0002, ADR 0005) and holds the History Lock and authentication window, exclusions, other devices, screen sharing and
  link previews (ADR 0003, ADR 0004, ADR 0005). Data opens with the backup status row, holds retention, backup, import
  and export, maintenance and Insights (ADR 0010, ADR 0011), and ends with **Start Over** (Clear Everything). The backup
  carries the settings (record kind 4, ADR 0010); there is no separate settings file.
- **Search goes to the row.** `SettingsIndex` (Core) lists every searchable setting; a view marks its row
  `.settingsRow("<entry title>")` and a pane's form carries `.settingsRowScrolling()`. A result selects the pane,
  scrolls the row to the middle and flashes an accent wash once, through `Motion.animation`. For Collections, Snippets
  and Version and build the pane is the answer.
- `ShelfKeyReference` (Core) lists the fixed keys that work while the shelf is open, shown read-only under Shortcuts, so
  they cannot clash with a recorded shortcut.

**Typed keys.** `SettingKey<Value>` (`Core/Runtime/SettingKey.swift`) is a name and a default for a `Bool`, `Int` or
`String`. `Setting` lists every preference and small piece of state kept in `UserDefaults`;
`@AppStorage(Setting.cardSize)` in a view and `AppDefaults.store.value(for: Setting.cardSize)` elsewhere read the same
default. A stored value of another type reads as unset. Nothing is registered at launch. A new key is one line in
`Setting` plus its entry in `Setting.allNames`. Keys owned by one policy (`PrivacyStats`, `ExclusionAllowances`,
`AutoBackupSettings`) stay with that type. `SettingsBackupManager` works by name from `Setting`, validating each value
by kind and range. Defaults in app-target enums (`CardSize`, `AppearanceMode`) are checked against the registry, not
imported into Core. Every AppKit string a person reads goes through `String(localized:)` (`makeItem` and
`AppState.attempt` take a `String.LocalizationValue`). The catalog has English only: strings are routed, not translated.

**Shortcuts.** `GlobalShortcut` (Core) is the one list: label, two `Setting` keys (key code, modifier mask), default and
Carbon id. `HotkeyController`, `HotkeyRecorderField`, the conflict messages, the status menu and `SettingsBackupManager`
all read it.
- Six cases. Defaults: open the shelf ⇧⌘V and paste as plain text ⌃⌥⌘V. Paste the previous clip, show or hide the
  floating window, pause or resume capturing, and hide or show clip contents start **unset**, so nothing is claimed
  system-wide that the person did not ask for. Two keys are registered on a fresh install.
- ⇧⌘V stays the shelf default because people switching from other clipboard managers expect it, though it collides with
  "Paste without formatting" in some apps. The Shortcuts pane and the guide say so and offer Change. ⌃⌥⌘V avoids Paste
  and Match Style (⌥⇧⌘V). `DefaultShortcutMigration` runs once: a Mac that finished onboarding and never changed
  paste-previous keeps ⌥⌘V as the person's own choice.
- Storage: a modifier mask of 0 means "never changed" (the default, or none); `GlobalShortcut.disabledMarker` (-1) means
  turned off. The key code is not tested, because 0 is the A key.
- Carbon ids: 1, 2 and 12 to 15 belong to the list; 3 to 11 are the pinned-clip shortcuts ⌃1 to ⌃9.
- The recorder pauses Pesto's hotkeys while it listens (`GlobalHotkeySuspension`, `HotkeyController.suspend` and
  `resume`) and checks a combination with `HotkeyRecording.evaluate`: it needs ⌘, ⌥ or ⌃; ⌘ alone with a key every app
  uses is refused (`HotkeyPolicy`); it must not clash with another Pesto shortcut or ⌃1 to ⌃9; it must not be one macOS
  has switched on (`SystemShortcuts`, read from the system's own list). Esc cancels. A restored backup is held to the
  same rules; an unset-by-default shortcut with no modifier switches off.
- Double-press ⌘C to append sits in the same pane. It is off by default because it watches every ⌘C system-wide, and
  needs Accessibility.

## Consequences
- A new searchable setting is a `SettingsIndex` entry plus `.settingsRow`; a view with a shortcut recorder must suspend
  the hotkeys. A new global shortcut is a `GlobalShortcut` case plus two `Setting` keys.
- Enforced by `SettingsIndexDriftTests`, `SettingsIndexTests`, `ShelfKeyReferenceTests`, `KeyNavCoordinatorTests`,
  `SettingsPolishTests`, `SettingsRegistryTests`, `SettingKeyTests`, `SettingDefaultsAgreeTests`,
  `LocalizationRoutingTests`, `GlobalShortcutTests`, `HotkeyPolicyTests`, `HotkeyRecordingTests` and
  `DefaultShortcutMigrationTests`.
- If another app holds a combination, registration fails and the recorder row says so (`hotkeyConflictDetected`).
- A count in a sentence needs a plural catalog entry (`VocabularyTests`).
- Not built: a sync toggle (sync does not exist, ADR 0010) and an Advanced pane.

## Docs affected
`docs/guide/settings.md`, `docs/guide/shortcuts.md`, `docs/design-language.md`, `docs/feature-reference.md`.
