# Pesto Settings Redesign Specification (macOS & iOS)

Status: Approved HIG specification for single-viewport tidying across Mac Settings (`Sources/Features/Settings/`) and iOS Settings (`Sources/Mobile/SettingsView.swift`).

---

## Diagnosis (3 Perspective-Shift Lenses)

1. **50ms Cognitive Clarity:** Five of seven Mac panes (`General`, `Appearance`, `Privacy`, `Shortcuts`, `Data`) overflow the `720 pt` default height by `350–1,400+ pt`, burying essential controls (`Card size`, `Sensitive content`, `Clear Everything`, `Import`, `Shelf keys`) below the fold.
2. **Native macOS / iOS HIG Craft:** `SettingsPaneHeader` stacks `73 pt` beneath the split titlebar; `Appearance` stacks a `192 pt` live preview plus three `92 pt`-tall `PreviewPicker`s vertically; `Privacy` and `CaptureSettings` use inline `DisclosureGroup`s that trigger `AccessibilityAuditTests` `.disclosureTriangle` `"Action is missing"` warnings; `Shortcuts` draws 30 shelf keys inline (`~560 pt`); `Data` embeds four `SwiftUI Charts` (`InsightsView`) inline in a Settings `Form`.
3. **Ruthless Subtraction:** Multi-line explanatory essays live inside `Toggle` labels and 5–7 line section footers instead of concise single-line labels paired with `InfoPopoverButton` popovers and sheets.

---

## Shared Chrome & Primitives

1. **Window & Header (`SettingsWindowFrame.swift`, `SettingsView.swift`, `SettingsPaneHeader.swift`)**:
   - Bump `defaultSize` from `800×720` to **`820×750`** (keeping `minimumWidth: 760`, `minimumHeight: 640`, `maximumHeight: 780`).
   - Compact `SettingsPaneHeader` icon tile from `48×48` (`r=13`, `22 pt`) to **`36×36` (`r=10`, `17 pt`)**, `.padding(.top, 10).padding(.bottom, 10)`, and 1-line subtitle (no `.fixedSize(vertical:)`).
2. **`InfoPopoverButton` (`Sources/Shared/Components/InfoPopoverButton.swift`)**:
   - Replaces inline `DisclosureGroup`s with a `24×24` `info.circle` button opening a `300 pt`-wide popover (`.pestoQuiet()`, `.pestoCaption()`, explicit `.accessibilityLabel`).
3. **Compact `PreviewPicker` (`Sources/Shared/Components/PreviewPicker.swift`)**:
   - Parameterized `tileSize` (default `112×92`, compact `78×48` / `72×44`) and `cornerRadius` (default `12`, compact `8`–`9`).
4. **`SettingsStatStrip` (`Sources/Features/Settings/SettingsStatStrip.swift`)**:
   - Tightened `.padding(.vertical, 6)` and `.headline.monospacedDigit()` values.

---

## Per-Pane Targets

| Pane | Target | Key Layout Changes |
|---|---|---|
| **General** | Single viewport (`~575 pt`, zero scroll) | Drop healthy `LoginItemToggle` caption; move Update check caption + `Check Now` + `InfoPopoverButton` to footer; put `Show suggestions` + `Reset Suggestions` on one row; inline AI status before switch; compact 1-line section footers. |
| **Appearance** | Single viewport (`~660 pt` total, zero scroll) | Scale `SettingsShelfPreview` to `0.50`; `16:9` `ThemePicker`; `34×34` `AppIconPicker`; inline `Accent color` name; compact dark-mode theme row/popover; pair `Shelf surface` & `Shelf position` side-by-side (`78×48` pickers); keep `Cards` directly above shelf section. |
| **Privacy** | Single viewport (`~585 pt`, zero outer scroll) | Compact `"Encrypted on this Mac"` header + `"Details…"` sheet + 2×2 `privacyFact` grid + `InfoPopoverButton` (replaces `DisclosureGroup`) + 1-line left-out count footer; `History lock` with `InfoPopoverButton`; `Add App…` in `App exclusions` header with bounded `92 pt` `ScrollView` (single-line rows, bundle ID in `.help`); compact `Sensitive content` picker (`72×44`) + `InfoPopoverButton`; merge `Other devices`, `Screen sharing`, and `Load link previews` into one `"Other devices & Network"` section with `InfoPopoverButton`s. |
| **Shortcuts** | Single viewport (`~585 pt`, zero outer scroll) | Condense `Everywhere` footer + `InfoPopoverButton`; bound `Pinned clip shortcuts` above 3 rows; bound `On the shelf` 2-column grid in a `175 pt` `ScrollView` + `"Full Reference…"` sheet (untruncated `.lineLimit(2)`). |
| **Collections** | Dynamic list | `26×26` collection icon badge; hide drag footer when `< 2` collections; merge suggestion groups into one `"Suggested"` section with inline subheaders. |
| **Snippets** | Dynamic list (`~560 pt` base) | Keep exact `SnippetsPaneOrderTests` section order and no `DisclosureGroup` on placeholders; 1-line empty state (`34 pt`); 3-column `Placeholders` grid (`4` rows); 1-line explanation + `See the guide` row; compact 1-line `Remember fill-in values` & `Suggestion statistics`; tighten `SnippetEditorView` editor/preview min/max heights. |
| **Data** | Single viewport (`~600–615 pt`, off-state) | Preserve `DataPaneLayoutTests` (`BackupSettings` first, `Backup` before `Sync`); move `InsightsView` into a sheet opened from `"View Insights…"` (keeping `HistoryLockGate { InsightsView() }` in `SettingsPanes.swift` for `SettingsLockGateTests`); compact `Backup`/`Sync` 1-line captions; compact `History` retention; 2×2 checkbox `Grid` for `Clean up copied text`; merge `Insights` + `Rebuild` into `"Insights & Maintenance"`; 1-line `Start over` footer; update `SettingsPolishTests.test_settingsSearch_scrollsToARowThatStartsBelowTheFold` to scroll a genuinely long pane (`Snippets` with seeded items or `Data` with Backup+Sync enabled). |
| **iOS `SettingsView`** | Compact flat sheet (~1.15 screens) | Merge `Clipboard` + `AutoFill`; merge `Screen capture` toggles into `Privacy`; trim multi-sentence footers to 1–2 crisp lines while keeping all UI-tested `MobileAccessibilityID` identifiers directly accessible on root. |

---

## Preserved Invariants

- All 48 `SettingsIndex` anchors and `.settingsRow("<title>")` calls (`SettingsIndexDriftTests`).
- `DataPaneLayoutTests`, `SnippetsPaneOrderTests`, `SettingsLockGateTests`, `QuietTextScanTests`, `SelectableTileScanTests`, `TypographyTests`, `VocabularyTests`.
- `CaptureSettings.encryptionCaption`, `ContentFilterNotice.text(...)`, `PrivacyNetworkFacts`, and `SyncCopy` remain intact for unit/regression tests.
