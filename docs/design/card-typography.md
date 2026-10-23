# Shelf card typography: let the clip be the loudest thing on its card

**Design only: needs your
eye before any SwiftUI changes.**

## What is true today
- Body text is 13 pt at the Medium card (200×180), scaled with the card width (`CardTextScale`, 0.85 to 1.2), at 88%
  primary. The header title is `.caption.weight(.semibold)`, 10 pt, and the time is `.caption2`
  (`ClipboardCard+Parts.swift`, `cardHeader`).
- So the title is not oversized in points. The header is loud for other reasons: a 44 pt band, a 26 pt app tile, a
  semibold title, and a wash made of the theme accent at 8% plus the source app's color at 55% (ADR 0013).
- Sizes are Small 160×140, Medium 200×180 (the baseline) and Large 240×220. The body gets
  `(height − 44 − 34 − 10) ÷ (18 × scale)` lines: 3, 5 and 6.

## Status
Option B is implemented (2026-10-21): `CardLayout` (Core) holds the header height, tile size, the gap under the header
and the footer reserve; `ClipboardCard+Parts.swift` and `RemoteSourceTile` use them. The check on a real shelf with all
four themes is still a hand check (`docs/testing.md`, "Before a release").

**Correction to the table below.** The formula `(height − 44 − 34 − 10)` left out the 2 pt gap under the header, and B
makes that gap 6 pt, so a 34 pt header would give Small only 3 lines. The footer is about 28 pt (row, bottom padding,
spacer), not the 44 pt the old terms reserved, so `CardLayout.footerReserve` is 36 and the result is 4, 5 and 6 lines at
the three sizes, as `CardLayoutTests` asserts.

## Skeptical reading of the item
"Rebalance so the clip is the focal point" is mostly right, and the fix is not a smaller title. Shrinking the title's
point size would put it at 9 pt, below `TypographyTests`' 10 pt floor and below what reads. The levers are the band's
height, the tile, the weight and the wash. The item also hopes for more room for the text. The arithmetic says that is
smaller than it sounds:

| Header | Small | Medium | Large |
|---|---|---|---|
| 44 pt (today) | 3 lines | 5 | 6 |
| 36 pt | 3 | 5 | 6 |
| 34 pt | **4** | 5 | 6 |
| 28 pt | 4 | **6** | 6 |

A 36 pt header gains no line at any size. 34 pt gains one, at Small only. Medium needs 28 pt, which cannot hold the
badges and a 20 pt tile. The honest gain is calm, not capacity.

## Proposal
Option **A**, the quieter header, and option **B**, A with a softer wash, are on the canvas next to today's card.

| | Today | A | B |
|---|---|---|---|
| Header height | 44 | 34 | 34 |
| App tile | 26 | 20 | 20 |
| Title | caption, semibold | caption, medium | caption, medium |
| Time | caption2, quiet | unchanged | unchanged |
| App-color wash | 55% | 55% | 32% |
| Theme accent wash | 8% | 8% | 8% |
| Body opacity | 88% | 92% | 92% |
| Space between header and text | 2 pt | 6 pt | 6 pt |

My pick is **B**, with a condition: look at it on a real shelf with all four themes before accepting. The wash is how a
card says which app it came from at a glance across ten cards; 32% may be too little on Parmesan and Pine nut, and the
app tile is now smaller. If it is, fall back to A.

Not changed: the footer (`caption2`), the badge sizes, the pin, the hotkey keycap, the corner radius, the hover card.

## What a change would touch
- `ClipboardCard+Parts.swift`: `cardHeader` (height, tile, title weight, the two washes, `themeWashOpacity` and
  `appWashShare`), `cardBody` (opacity, top padding), `textLineLimit` (the `44` becomes the header constant, so the
  formula and the header cannot drift apart again).
- `CardMetrics` or `CardTextScale`: the header height belongs in Core beside the formula, with a test that the line
  counts are 4, 5 and 6 at the three sizes.
- `TypographyTests.fixedSizeFontsAreScaledOrAllowlistedIcons` counts `.font(.system(size:` per file: an edit that adds or
  removes one in `ClipboardCard+Parts.swift` must change the number there.
- The card is also drawn by `SampleCardStrip` (Appearance preview, onboarding), so those change with it.
- Snapshot baselines in `Tests/PestoSnapshotTests/__Snapshots__/ClipboardCardTests` were last recorded on 2026-09-25,
  before the header began naming the app (c5288e8) and the text began following the card size (8f5c27c), so they are
  already stale; they must be re-recorded on a macOS 26 Mac either way.

## Website (`Shelf.astro`, spec only; nothing in the website repository was edited)
`src/styles/home.css` in the website repository:

| Rule | Today | B |
|---|---|---|
| `.sc-head` band | 2.75rem | 2.125rem |
| `.sc-head i` tile | 1.625rem square | 1.25rem square |
| `.sc-head b` | `font-size: 0.75rem; font-weight: 650` | `font-weight: 550` |
| `.sc-head small` | inherits `--text` | muted, as the app's quiet color |
| header wash | app color at full strength | app color at about 60% of today's |
| `.sc-body` | inherits `--text` (already full strength) | unchanged: the app's body goes from 88% to 92%, the site's is already 100% |

`.sc-body--long` keeps `-webkit-line-clamp: 4`; the website card is not tied to the app's line formula. The full, implementable hand-off is `docs/design/website-shelf-spec.md`.

## Found
- The task note called the Medium card "Large"; Medium is the baseline and the default.
- The website lets `small` inherit the full text color, so its time reads as loudly as its title; the app's is quiet.
