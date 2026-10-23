# 0013. Four themes share one identity with the icons, a theme owns the shelf's colour, and the shelf opens at the Bottom or the Top

Status: Accepted

## Context
Pesto's look has to hold across light and dark, a Liquid Glass shelf, the Dock, the menu bar and Reduce Motion. Left to
taste, things failed: an accent passing on a dark ground failed as text on a light one; themes differing by a few units
looked identical in dark; "System" accent drew system blue; a custom Finder icon invalidated the code signature; forcing
Light on a dark Mac drew the menu-bar icon dark on a dark bar; a theme was only a ring and a faint wash while card
headers carried the source app's colour; and a filled button printed white on a light green at about 2.2:1.

The shelf's second position was once named for the notch, but it hangs from the bottom of the menu bar on every screen,
so a Mac without a notch showed a setting named for hardware it does not have.

## Decision
**Themes** (`AppTheme`, `Setting.appTheme`, default Basil), in this fixed order: **Basil, Parmesan, Pine nut, Mortar**
(three ingredients, then the bowl). A theme is an accent pair (light, dark), a wash over the shelf's glass per
appearance, and a paired icon. Basil is the brand look with no wash.
- The wash (`ThemeTintLayer`, in `ShelfBackground` and the Settings preview) is at most 0.6 opaque: the shelf stays
  glass. Cards stay material with adaptive borders.
- Contrast is data (`AppThemeTests`): each wash blended over the plain ground must keep the accent at 4.5:1 and primary
  text at 7:1, in both appearances. For every pair of themes, in light and dark, the CIE76 distance between grounds plus
  between accents is at least **22**. Mortar's ground alone differs from Basil's by at least 6. A theme that cannot meet
  this is removed, not tuned to the line. Parmesan's accent is gold text (`7A5F00` / `E3C04A`), never the gold fill.
- **Mortar** is the only low-chroma theme (the shelf that recedes). Its ground is cool stone: a `7A90A8` wash at 0.20
  over garlic in light (`E0E2E0`) and `000408` at 0.60 over the dark surface; its accent is `3F5446` / `B9CDBF`.
- Picking a theme writes the theme, its icon and the accent `brand`; icon and accent can then change on their own.
  `Setting.appThemeDark` (empty means the same theme) picks a theme for dark mode in `AppTheme.resolve`; the icon cannot
  change with appearance and follows the light theme.
- **A theme owns the cards' headers**: every header carries the theme's accent at 8 percent
  (`ClipboardCard.themeWashOpacity`), with the source app's colour as a top-down fade at 32 percent (`appWashShare`)
  over it. The app colour still says where a clip came from.
- **A filled button is `PestoProminentButtonStyle`**: accent fill, label white or the dark brand ink, whichever reads
  better (`ContrastRatio.labelHex(onFill:)`). `AccentLabelTests` holds every theme and preset fill to 4.5:1.
  `.borderedProminent` and `.glassProminent` are banned in `Features`, `Shared` and `App` (`AccentUsageTests`).

**Accent** (`AccentChoice`, `accentColorHex`): the theme's own accent first; then presets (`AccentPreset`: blue, purple,
pink, red, orange, graphite) with a light and a dark shade, each at 4.5:1 as text on its ground and at least 40 (sRGB)
from every theme accent (`AccentPresetTests`); then Other…, the system color panel (`AccentColorPanel`), closed when a
preset or the theme is chosen, the pane is left or Settings closes. Green and yellow are not offered. Old system-accent
values read as the theme's accent. Views draw with `@Environment(\.pestoAccent)`, never `Color.accentColor`, which
ignores `.tint`; chip text stays 4.5:1 on any accent (`TintedChipContrastTests`).

**Icon** (`AppIconChoice`, `Setting.appIcon`): `basil`, `parmesan`, `pineNut`, `mortar`, in the themes' order
(`AppIconOrderTests`), each named for its theme. One rule: the ground carries the theme, the cards stay garlic glass,
the P is the theme's light accent. A stored `gold` or `garlic`, in a preference or a backup, reads as Parmesan or Pine
nut (`acceptedStoredValues`). Basil is the bundle icon (`Sources/Resources/Pesto.icon`); the others are set with
`NSApp.applicationIconImage`, so they show in the Dock and app switcher. Art is `design/source/brand-art.py` and
`icon-layers.swift`. **The Finder icon never changes**: `NSWorkspace.setIcon` writes metadata into the signed bundle and
`codesign --verify --strict` fails.

**Menu-bar icon** is a template image (dims and tells VoiceOver while capture is paused or contents hidden; state
changes there are instant) and can be hidden (Settings → General); the shelf shortcut still works. Appearance flows only
through `NSApp.appearance`, never `.preferredColorScheme` at a root. It also reaches the status item's window, so
`applyAppearance` skips it (`MenuBarAppearance.isSystemChrome`). The bar's colour follows the wallpaper, not the Mac's
setting, so the button is pinned only when forcing the appearance changes what the status window reports, and then to
the bar's own answer (re-checked on theme, Space, display and wake).

**Motion** goes through `Motion.animation(_:)` (nil under Reduce Motion) with four names: `pestoQuick` 0.15 s ease-out,
`pestoMove` 0.22 s snappy, `pestoWash` 0.4 s smooth, `pestoPop` spring (response 0.3, damping 0.6). Panels slide only
when `PanelMotion.slides` says so. A UI-test launch turns motion off (`-UITestMotion` turns it on). No pulse per
captured clip, no looping animation.

**Shelf position** (`ShelfPosition`): **Bottom** and **Top**. The stored value of Top stays `underNotch`, because
earlier builds, `SettingsBackupManager` and backups hold it. Top hangs below the menu bar, and below the notch where
there is one. The hover card opens away from the shelf (`ShelfPosition.hoverCardOpensAbove(hostIsShelf:position:)`) and
the Settings preview draws the shelf at the named edge. Any slide keeps the layer-transform invariant in
`Features/Overlay/CLAUDE.md`.

## Consequences
- A new theme must pass the contrast, wash and distinctness tests, have a paired icon in the same position, and be added
  to `AppIconChoice`; a new window root reads `@AppStorage(Setting.appTheme)`.
- Tests: `AppThemeTests`, `BrandPaletteTests`, `AppIconChoiceTests`, `MenuBarAppearanceTests`, `MotionTests`,
  `MotionRoutingTests`, `TypographyTests` (no fixed font under 10 pt).
- Light, Dark and System and a custom accent repeat System Settings, kept on purpose: contrast is tuned per appearance
  and the shelf follows the theme's ground. System stays the default.
- Not built: a floating or side shelf, a per-display position, a choice of display (`TargetScreen` uses the frontmost
  window's display, then the pointer's), per-theme card materials, a themed menu-bar glyph, a fifth theme.
- The toast and the Paste One by One panel do not follow the position and can overlap a Top shelf; `docs/testing.md`
  lists the hand checks.

## Docs affected
`docs/guide/settings.md`, `docs/feature-reference.md`, `docs/design-language.md`, `docs/retired-terms.txt` ("Under the
notch"), `docs/testing.md`, `README.md`, `CHANGELOG.md`.
