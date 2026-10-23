# Design language

One look across the shelf, Settings, the About window, the icon and the website. The palette comes from
`BrandPalette` (`Sources/Core/Runtime/BrandPalette.swift`); the website's tokens are `src/styles/tokens.css` in the
website repository.

## Rules
1. **Basil is for action and focus.** Accent colors draw through `@Environment(\.pestoAccent)`, never
   `Color.accentColor`. Grounds are garlic, parmesan and pine nut in light and mortar and `1F2320` in dark, never pure
   black; the one exception is Mortar's dark ground, a near-black `0C1012` (ADR 0013) so the four themes tell apart. Gold is a glow, and gold text only as `7A5F00` / `E3C04A`.
2. **Glass is chrome, not content.** The shelf is one glass surface; cards are material with a hairline border; Settings
   uses the system grouped form.
3. **Settings, pane by pane.**
   - Every pane opens with `SettingsPaneHeader`: a 48 pt tile (accent glyph on accent at 16%), the pane name in
     `.title2.bold()`, one sentence in 70% primary, and the pane's main action at the right. It stays above the form
     (`settingsPaneTop`, a safe-area inset, so the form is still the pane's root and the toolbar behaves). What it pins
     has an opaque window ground and a hairline under it: rows scroll beneath an inset, and without a ground they
     show through its text.
   - A row the search can find carries `.settingsRow(...)`: choosing a result scrolls it to the middle and washes it
     in the accent for a moment (`pestoWash`, nothing under Reduce Motion).
   - The accent row follows macOS: the theme's own color first (that is what "Multicolor" means for an app with its
     own color), the named presets, then *Other*, with the selected name under the row's title.
   - A setting shows its state on its own control. A read-only row that repeats a toggle is a bug.
   - Settings come first, information after, anything that deletes last.
   - A picture goes beside the controls it pictures: the Appearance preview follows Appearance only, and the content
     filter keeps its own inline picture in Privacy.
   - Numbers that head a pane are `SettingsStatStrip` tiles; the promise Privacy opens with is one card.
   - Shortcuts are `Keycap`s, as on the website's `kbd`.
4. **Themes show both modes.** A theme card is half light and half dark, drawn from the theme's own ground, wash and
   accent (`ThemeShelfMiniature`). `AppThemeTests` requires every theme to read (4.5:1 accent, 7:1 text) and every pair
   of themes to differ (ground and accent distance of at least 20, CIE76) in light and dark; a theme that cannot pass both
   is removed, not tuned until it squeaks by.
   Each theme has one icon, named after it: the ground carries the theme, the cards stay garlic glass and the P is the
   theme's accent, a deep color that reads on the card (ADR 0013, `design/source/brand-art.py`).
5. **Words:** American English, Title Case for buttons and menu items, sentence case for labels, headers and captions
   (`docs/copy-guide.md`). No emoji, no exclamation marks.
6. **The hover card is content on card material, not glass** (ADR 0009): 320 pt, radius 16, a hairline, one footer line of
   facts and no buttons.
7. **Motion** goes through `Motion.animation`, one idea per moment, off under Reduce Motion. Humor lives in pictures
   (the leaf, the jar), never in controls.

## Where things are
| What | File |
|---|---|
| Pane header, stat strip | `Sources/Features/Settings/SettingsPaneHeader.swift`, `SettingsStatStrip.swift` |
| Theme cards and miniatures | `ThemePicker.swift`, `ThemeMiniature.swift` |
| Appearance preview | `SettingsShelfPreview` in `AppearancePreviews.swift` |
| About window | `AboutView.swift`, `Sources/App/AppDelegate+About.swift` |
| Theme values | `Sources/Core/Runtime/AppTheme.swift`, ADR 0013 |
