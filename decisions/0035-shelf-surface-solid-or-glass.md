# 0035. The shelf is solid by default and glass by choice

Status: Accepted

Nothing about the network, storage, backup or sync changes. It supersedes the glass parts of ADR 0013 (the shelf "stays glass underneath"; the wash is drawn over glass) and the glass rule in `docs/design-language.md`. The rest of 0013 (themes, accents, position) stands.

## Context
The shelf was always Liquid Glass, with a theme wash and the focused card's colour over it. `AppThemeTests` check each theme's accent at 4.5:1 and its text at 7:1 on the theme's ground, but that ground is a fixed colour; real glass shows the desktop. A consultant measured the gate's real-desktop screenshots: the light shelf's ground read about `A3A4A3` where the tests assume `FAF7EE`, ink fell from 12.7:1 to 5.4:1 and the accent to about 2:1 on the chip row; dark chip and age text sat near 3.4:1. The pictures the docs use stand on a calm gradient and flatter the glass. Michael likes the glass and the wash, and asked for a choice, with a slider rejected (a middle position is an unmeasured look whose contrast no test can promise) and solid as the default.

## Decision
- **`ShelfSurface`: `glass` or `solid`, stored as `Setting.shelfSurface`, default `solid`.** Nothing stored, or something unknown, reads as solid. A backup restores only a known value.
- **Solid is the theme's own ground, fully opaque** (`AppTheme.groundHex`, the colour the tests already check, with the theme wash blended in once), so `ThemeTintLayer` is not drawn on it. Glass is what it was: `.glassEffect` on macOS 26 and later, a material before.
- **Reduce Transparency always gives solid** (`ShelfSurface.drawsGlass`). The choice is kept and the Appearance pane shows Solid selected, disabled, with the reason and a button that opens System Settings' Display pane.
- **The focused card's colour wash is full strength on glass (0.22, 0.12, 0.18) and 35 percent of that on solid** (`ShelfSurface.washOpacities`), chosen by Michael from board 2. Over an opaque ground the full wash reads heavy; at 35 percent it moves a corner colour by about 5 to 9 CIE76, a tint seen only beside the plain ground.
- **Cards are never glass.** On a solid shelf a light card is opaque white (white at 0.58 over a near-white ground only greys it); a dark card stays white at 0.10. The card reads the surface through `shelfDrawsGlass`, an environment value set once at each shelf root (`shelfSurfaceEnvironment()`), never the setting itself, so no card does a defaults read. Outside a shelf (snapshots, previews) the value is nil and a card keeps its earlier fill.
- **Settings → Appearance → Shelf surface**, between Cards and Shelf position: two pictures (`ShelfSurfacePreview`), indexed in search ("glass", "solid", "transparent", "see-through", "wash").

## Consequences
- Every install that never chose gets the solid shelf on update. The pictures, the film and the website demo still show glass until retaken (`make pictures`, `make teaser`); the website's `.shelf` follows in its own pull request.
- The glass view is not created on a solid shelf, but no speed gain was measured in the app's own process. A/B on the Debug UI-test build, runs interleaved (2026-11-06, a Mac under other load): shelf open median 79 ms solid against 82 ms glass over 20 opens each, with a spread of 49 to 97 ms (the first open of a launch is about 430 ms on both); scroll over the 5,000-clip history 8.7 to 9.0 s and 3.1 to 3.4 s of app CPU on both, three runs each. Any glass cost is in WindowServer and the GPU, which these numbers do not see; `make bench-latency` and `make bench-scroll` stay the authority and have not run.
- Solid cannot fail the contrast the tests assert, on any desktop. Glass can, as before; Reduce Transparency and Solid are the answers.
- The hairline carries a light card's edge on solid: white on a near-white ground is about 1.07:1, so the existing 0.14 hairline and the shadow draw it (unchanged; a stronger one is a hand-check call). `ShelfSurfaceUITests` open the shelf on both surfaces; whether the edge reads is a hand check.

## Docs affected
- `docs/design-language.md` (rule 2), `AGENTS.md` (the Liquid Glass line), `Sources/Features/Overlay/CLAUDE.md`
- `README.md`, `docs/feature-reference.md`, `docs/guide/settings.md` (synced to the website), `docs/testing.md` (wallpapers hand check)
- `decisions/README.md`
- Website: `src/styles/home.css` (`.shelf`), the shelf spec in `docs/design/website-shelf-spec.md`
