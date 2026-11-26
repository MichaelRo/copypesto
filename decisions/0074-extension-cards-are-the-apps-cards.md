# 0074. Extension cards are the app's cards

Status: Accepted (owner, 2026-11-26, backlog triage and expert consult)

Closes ADR 0068's open consequence (the keyboard, AutoFill and the widgets showed neither the app's icon nor the foot
glow). Amends ADR 0066 (the keyboard's "Pesto" chip and its settings panel) and ADR 0063 (switching the search page's
layout). Encryption at rest and what the sealed files may hold about a clip's content are unchanged.

## Context
The keyboard and the AutoFill picker each drew their own card, and AutoFill's had a footer of its own; neither showed
the source app's icon or the glow the iPhone library card has (ADR 0068), and the widget tile showed neither either.
The sealed quick-insert set and widget snapshot did not carry what those need. The keyboard's size preview showed one
row whatever the size, the app's settings showed none, and the settings chip read "Pesto" in Pesto's own keyboard.
The search page switched layouts only by holding space, which Apple's keyboard uses for the cursor.

## Decision
- **The sets carry the look:** `QuickInsertEntry` and `WidgetClip` carry the clip's source bundle ID and color
  (`SourceAppLook`: `#RRGGBB` only, never the placeholder grey; none for a clip from another device's clipboard; on
  the iPhone a clip without a sampled color takes the color a Mac's catalog gave its app). `QuickInsertSet` and
  `WidgetSnapshot` carry each listed app's PNG icon once (`SourceAppIcons`: at most 8 KB each; 12 apps and 48 KB in
  the quick-insert set, 24 and 96 KB in the snapshot, on top of the clips' budgets). Older files open with none.
- **Icons attach after the clips are chosen** (`attachingAppIcons`), on the main actor where they live: the Mac's
  `SourceIconCache` for its widget snapshot, the iPhone's `SourceAppCatalogStore`. The menus drop them while locked.
- **One card:** `QuickInsertCardFace` (`Sources/MobileShared`) draws the keyboard's, the AutoFill picker's and the
  size preview's cards: fill, hairline, `CardFace`, the glow (`CardGlow`, stretched on the keyboard's short card) and
  `CardFootLineView` led by the icon. The widget tile, shared with the Mac and without `MobileShared`, draws the same
  glow and icon, only in `.fullColor` rendering, never on a picture or a color.
- **The size preview** (`KeyboardSizePreview`) shows the cards at their true size in as many rows as the keyboard
  will (`KeyboardLayout`, now shared): in the keyboard with the person's own clips, in Pesto's Keyboard & AutoFill
  page with made-up sample clips, framed as the keyboard.
- **The settings chip is a gear alone** (VoiceOver: Keyboard Settings); the panel reads "‹ Clips · Keyboard Settings
  · ↗" (the arrow opens Pesto with Full Access, ADR 0072).
- **A language key, not a globe:** the search page shows the active layout's two capitals ("EN", "HE") beside 123
  when the person has two or more layouts, and a tap moves to the next. iOS's globe already means "leave this
  keyboard"; a second globe that only changed the letters would mean two things. Holding space still switches.

## Consequences
- A clip from the iPhone itself has no app, so its card glows in the theme's hue only, as in the library.
- Past the 12th app in the quick-insert set (the 24th in the snapshot), or past the icons' bytes, a card has no icon
  and its foot line falls back to its device symbol; text clips' apps are counted before pictures', which AutoFill
  does not show. An app the Mac cannot find gives no icon rather than the disk's. A bundle ID is carried only as
  Apple spells one (letters, digits, dots, hyphens, underscores; at most 160 characters).
- The language key names the layout, not the language: a Serbian (Latin) keyboard uses QWERTZ and shows "DE", as the
  space bar named it before.
- Whether the glow and the 13–16 pt icons read on a keyboard and a widget, and the key's fit on a small iPhone in
  landscape, are hand checks (`docs/testing.md`).

## Docs affected
- `AGENTS.md` (what the two sealed files hold), `docs/guide/privacy-and-security.md`, `docs/app-store-ios.md`
- `docs/design/ios-keyboard.md`, `docs/testing.md`, `decisions/README.md`
