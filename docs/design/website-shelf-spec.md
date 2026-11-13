# Website hand-off (2026-10-21): shelf cards, and what the site should now say

Later changes to the shelf and its cards, and to words the site repeats, are in
[`review-fixes-website-spec.md`](review-fixes-website-spec.md) (2026-10-22).

**The shelf's ground (2026-11-06, ADR 0035).** The app's shelf is solid by default: the theme's own ground, fully opaque, with a soft wash of the focused card's colour; Glass is a choice in Settings. The site's demo shelf (`.shelf`) is therefore a solid `var(--bg)` with the hairline and shadow it had, no `backdrop-filter`; its hover card keeps card material.

## Brief for the website agent (paste this first)
> You are working in the the website repository repository. Nothing in it was edited from the app repository; this file is the whole
> spec. Do three things, in this order, and open one pull request per part. (1) **Cards:** make the sample shelf cards in
> `Shelf.astro` and `src/styles/home.css` match the app's cards exactly, using the numbers in "Values" and the rules below.
> (2) **Copy:** update the feature, guide and FAQ text named in "What the site should say". (3) **Check:** run the checks in
> "Check", and attach before/after screenshots of every tone in light and dark next to the app pictures listed under
> "Reference pictures". Do not invent features: say only what this file says. Never claim sync, an iPhone app, the Mac App
> Store or cloud AI. UI text is American English; menu items and buttons are Title Case, labels and captions sentence case.
> If a value here disagrees with the site's current CSS, keep the intent (a quiet header, the clip text the loudest thing)
> and tell the app side what you changed and why.

## Part 1: shelf cards in `Shelf.astro`

For whoever implements it in the the website repository repository (nothing in that repository was edited from here). The goal
is the same picture as the app, not a similar one: the site's cards, the welcome screen's strip and the Appearance
preview are all the app's real `ClipboardCard` (`SampleCardStrip`), so the numbers below are the ones the app draws.
They mirror option B of `docs/design/card-typography.md` and the display rules of `docs/design/card-whitespace.md`
(both approved 2026-10-21). The website values were read from `src/styles/home.css` and `src/components/Shelf.astro`
on 2026-10-21; if either has changed, keep the intent: a quiet header, the clip text the loudest thing on the card.

Points convert at 1 pt = 1 px = 1/16 rem. **Every change to a card or the shelf in the app updates this file in the same
pull request** (`CardSpecDriftTests` fails when the numbers in the first table stop matching `CardLayout`).

## Values (from `CardLayout`, tested)
| Part | App | Website |
|---|---|---|
| Space above the content | 10 pt | 0.625rem |
| Source tile | 18 pt | 1.125rem |
| Gap between paragraphs | 6 pt | 0.375rem |
| Footer reserve | 36 pt | 2.25rem |

**No header band since ADR 0044 (2026-11-12):** the content starts 10 pt under the card's top edge and one line of
facts sits at the foot (shortcut number, an 18 pt source tile, the app's name and the age; the size joins on focus or
hover; then expiry, snippet, shortcut, pin and collection). On a picture every part of that line sits on
the pill ground and there is no scrim; on a color it is the fill's own ink. The site's demo shelf was redrawn to this card (website PR 107); the sections below that still describe a
header, a wash or a scrim are history, and the picture and color rows of the treatments table are current.

Medium card, 200 × 180 pt (aspect 10 / 9): 10, then 7 lines of text (7 × 18 = 126), then the line of facts. Small
(160 × 140) shows 6 lines, Large (240 × 220) shows 8.

## `src/styles/home.css`
| Rule | Now | Change to |
|---|---|---|
| `.sc` first background layer | `color-mix(in srgb, var(--tint) 55%, transparent) 0, transparent 3.1rem` | `color-mix(in srgb, var(--tint) 32%, transparent) 0, transparent 2.5rem` |
| `.sc` accent band | `top / 100% 2.75rem no-repeat` | `top / 100% 2.125rem no-repeat` |
| `.sc:has(input:checked)` | the same two layers, repeated | the same two changes, so a selected card matches |
| `.sc-head` gap | `0.5625rem` | `0.5625rem`, unchanged (the app's header gap is 9 pt) |
| `.sc-head i` | `1.625rem` square, `border-radius: 8px` | `1.25rem` square, `border-radius: 5px` |
| `.sc-head i svg` | `1rem` | `0.6875rem` (the app's glyph is 11 pt in a 20 pt tile) |
| `.sc-head b` | `font-weight: 650` | `font-weight: 500` (the app's medium); keep `0.75rem` |
| `.sc-head small` | inherits `--text` | `color: var(--muted)`, the app's quiet color |
| `.sc-body` | inherits `--text` | `color: color-mix(in srgb, var(--text) 92%, transparent)`; `padding-top: 0.375rem`; font `0.8125rem`, line height `1.125rem` (`0.75rem` and the same line height for code) |
| `.sc-body--long` | `-webkit-line-clamp: 4` | `-webkit-line-clamp: 5` when the card is drawn at the Medium size above |

The three tint wash rules appear in three places (`.sc`, `.sc:has(input:checked)` and any dark-mode override of them in
`tokens.css`); search for `3.1rem` and `2.75rem` to find every one. The flat theme wash under the app color (the theme
accent at 8%) is unchanged.

## A lone glyph
A text clip that is exactly one emoji or symbol (`CardPreviewText.isSingleGlyph`: one character, emoji presentation or Unicode category So, Sm or Sc) is centered in the body at 64 pt (scaled by `CardTextScale`) with no margins; header and footer are unchanged. Secrets and hidden clips never take this layout. References: `test_singleEmojiCard.{1,light}.png`, `test_singleSymbolCard.{1,light}.png`.

## Content-first cards (ADR 0026)
Decided by `CardTreatment` (Core); the site's demo shelf follows it (website PR 107). Tile, corner and rings are as above unless said; there is no header (ADR 0044).
| Clip | Card |
|---|---|
| Picture, GIF | The picture fills the card edge-to-edge (`object-fit: cover`, no top margin, no scrim). The one line of facts sits at the foot on a pill ground (`PictureScrim.pillOpacity`; `var(--card-bg)` at 85% with a 1 px `var(--line-strong)` outline): the shortcut number, the 18 px source tile, the app's name (not "Image" or "GIF") and the age; a GIF also has a "GIF" pill at the right, which a narrow card drops before the age. The size joins the line on the focused or hovered card. No paste count; a collection badge and tag chips sit on the same pill ground. |
| Color | The card is the color. The text is 26 px semibold (15 px if longer than 9 characters) bottom left, 12 px in, above the line of facts, which is drawn in black or white ink at full strength (the higher WCAG contrast on the fill) with an outlined shortcut pill in the same ink; only the app's name is shortened when the card is narrow. |
| One line of text, 48 characters or fewer (ADR 0031) | Body in 600 weight, line height 1.25. Up to 24 characters (counted as visible characters, after trimming spaces and line breaks; an emoji or accented letter is one): 24 px, at most 2 lines. 25 to 48 characters: 18 px, at most 3 lines (fewer when the card is too short). Both scale with the card size like other body text; they do not grow with the browser's text size. The first line's capital letters sit 12 px under the header's bottom edge on both sizes (24 px: line box starts 6 px under it; 18 px: about 1.5 px lower, so the capitals line up). Header and footer as for text. A lone emoji or symbol keeps the glyph layout. |
| Link, no preview picture (ADR 0031) | The host (lower case, user info dropped, never the page's own site name) at 24 px semibold up to 24 characters of host, 18 px semibold beyond; no smaller step. It stays on one line, never wrapping mid-host: it shrinks with the card width down to 0.7 of its size, then ends in an ellipsis (the website demo already does this). Beneath it the port and path (no query) at 11 px in the muted color, in the room left (up to 3 lines on Medium and Large, 2 on Small, none if there is no room). The first line's capitals sit 12 px under the header, as for text. A link with a preview picture keeps its picture body. |
Unchanged: code, multi-line or long text, every file card, anything hidden, masked or covered.

## Covered cards (ADR 0028)
A card covered for a screen share (or by Hide Clip Contents) is the standard card shape, an opaque surface with the card material over it and no content (`CoveredCardFace`, facts from `CoverFacts` in Core). It draws exactly three facts and nothing else:
- Top left: the shortcut number (cards 1 to 9) in a 4 px radius outlined pill, 11 px medium (`caption2`), gray at 60%.
- Top right: the relative age, 11 px, quiet gray.
- Centre: the `eye.slash.fill` symbol at title size, the kind as one plain word (Text, Link, Image, File, Color, Code) at 11 px medium, and the Show link at 11 px. A masked secret and any clip with a sensitivity category read "Text".

Never drawn: the source app's tile or name, the category, a size or length, a title, a file name, a link's domain, a color's hex or tint, a picture. A focused or selected covered card draws its 1.5 px accent ring over the cover.

The content-filter blur uses the same face and adds one 11 px line, "Sensitive content", between the kind and Show. Its context menu stays complete; the share cover's menu and VoiceOver actions are Paste, Paste as Plain Text, Copy, Delete and Show only.

The site's demo shelf draws one covered card (the first), as this section says: the ⌘ number top left, the age top right, the `eye.slash` symbol, "Text" and the Show link, nothing else (Show is decorative on the site); its spoken label and hover facts say no more. It follows this section and is changed in the website repo.

The demo draws only kinds the app has (text, link, image, file, color, code). A PDF or a video is a File card (icon, name, folder, size), a lone emoji is a Text card set large (the single-glyph layout above, "1 character" in the foot), and Swift, JSON and Markdown clips are Code cards headed "Code" with the language in the foot facts.

The demo's picture hover card follows the app's for a picture that has text (ADR 0034): the picture, a "Text in the picture" box of the note's tint, then the facts line. The demo's box has no Copy Text button, because the demo has no script; the app's has one. Changed in the website repo.

## Whitespace (`card-whitespace.md`)
The app compacts a clip for display (a pure function, `CardPreviewText.display`); hand-written samples can follow the same
rules by writing them that way:
- No blank lines or spaces at the start, no whitespace at the end, never two blank lines in a row.
- A blank line between paragraphs is a **gap**, not a text line: write each paragraph as its own element and put
  `<i class="sc-gap" aria-hidden="true"></i>` between them.

```css
.sc-gap {
  display: block;
  height: 0.375rem;
  background: radial-gradient(circle at 0.5px 50%, var(--muted) 0.5px, transparent 0.6px) 0 0 / 4px 100% repeat-x;
  opacity: 0.5;
}
```
- A gap costs 6 px of the body's height, so the same clamp shows a little more text. Clamp by height, not only by lines:
  `max-height: 5.625rem` (5 lines) with `overflow: hidden` on the body, plus `-webkit-line-clamp` on a single paragraph.
- No glyph at a line break and no marker for trailing whitespace.
- In `Shelf.astro`, `measure(card)` returns `N characters`. When a text card's body has more than one line and the whole
  text is in the sample, return `N characters · M lines` (drop one trailing break, split on line breaks, as the app
  does). The footer text is `0.6875rem`, muted.

## Check
1. All four tones (`plain`, `green`, `blue`, `note`) in light and dark: the header still reads which app the card came
   from; if the 32% wash is too faint on a tone, raise it to 40% for the site and tell the app side.
2. `small` (the time) passes 4.5:1 in `--muted` on each card ground in both themes.
3. Hover, focus and checked states still look as they do (the `translateY(-6px)` lift and the accent ring are untouched).
4. Put a site card next to a screenshot of the app's Medium card (`.build/ui-screenshots/` after a gate run): header,
   tile, title and first line of text start at the same offsets.

## Reference pictures (the app drawn at its real size, macOS 27, `Tests/PestoSnapshotTests/__Snapshots__/ClipboardCardTests/`)
`test_textCard.1.png` (Medium, dark), `test_textCard_lightMode.light.png`, `test_textCard_small.1.png` (4 lines),
`test_textCard_large.1.png` (6 lines), `test_textCard_paragraphs.1.png` (gaps and the line count),
`test_textCard_perTheme.{basil,parmesan,pineNut,mortar}.png` and `test_textCard_rtl.rtl.png` (the layout mirrors). The design
canvas, with the old and new cards side by side, is in the maintainer's design files.
Two things to copy from them: the body text is dark on the light card (never white), and a text block holds its line count
plus 4 px (`CardLayout.lineTolerance`), so give the body `max-height` of the lines times 18 px plus 4 px.

## What the site should say (Part 2)
Only what the app does today. Where the site already has a page, edit it; do not add pages.
- **Importing:** Pesto offers to bring a history over from an installed clipboard manager, once, after setup. With one app
  found the shelf says "You have Maccy. Bring your history into Pesto?" with *Import…* and *Not now*; with several it names
  them ("You have Paste and Maccy", then "Paste, Maccy and 2 more" past three) and *Choose…* opens **Settings → Data → Found on
  this Mac**, a card with a row and its own *Import…* for each. Each import asks for Touch ID and a file of its own, so
  nothing is merged blind; there is no "import everything" button. Supported: Paste, Maccy, Alfred, CleanClip, PasteNow,
  CopyClip, PastePal, Pastebot, Clipy and Unclutter, and Flycut.
- **Other apps:** *Settings → Data → Another app's library → Import… → Other File…* reads a CSV, JSON or text file of clips
  that almost any manager can export: choose which column is the text, when it was copied and what is pinned (or what one clip
  is in a text file), see the usual preview, then import. Text only; secrets are masked; clips you have are skipped.
- **Open With on a card:** phone numbers (Call), emails, addresses and coordinates (Open in Maps, including `37.7749; -122.4194`,
  a space between, and degrees-minutes-seconds), dates (Add to Calendar), links, and carrier tracking numbers (UPS, USPS, FedEx,
  DHL: checked by their check digit, so a typo is not offered; a FedEx, DHL or 20-digit USPS number needs the carrier's name in the
  text). Colors: `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA` and `rgb()` / `hsl()` with commas or spaces are recognized as colors,
  and a four-letter hashtag such as `#cafe` is not.
- **Cards:** a text card shows its paragraphs with a slim dotted gap for a blank line and, when the whole clip is shown, a
  footer such as "64 characters · 8 lines". A card shows 4, 5 or 6 lines at the Small, Medium and Large sizes.
- **Troubleshooting ("Can't unlock your clipboard history"):** the alert offers *Quit*, *Start With Empty History* and
  *Restore from Backup…*. Restore opens a window where you choose a Pesto backup, enter its passphrase or recovery key and see
  what it holds; only the *Restore* button replaces the unreadable history, a wrong passphrase or *Cancel* changes nothing and
  brings the alert back.
- **Not yet, do not mention:** summarizing a long document one part at a time (designed, not built), flights, sync.

## Keeping it true
Any later change to a card or the shelf updates this file in the same app pull request; `CardSpecDriftTests` fails when the
numbers in "Values" stop matching `CardLayout`. The site's copy follows `docs/guide/` and `docs/feature-reference.md`, which
the release step syncs.


---

## Part 3 — Command bar chips (1.0.1: D3 & D4)

### Collection and app filter chips (D4)

- **In the app (`CollectionChip.swift`, `PestoChip.swift`, `AppChipsRow.swift`):**
  - **Collection chips (`CollectionChip.swift`):** Share the same 24 pt tinted capsule geometry, `.caption.weight(.medium)` typography, 9 pt horizontal padding, fill opacity (`0.10` rest, `0.18` hover, `0.25` selected), and border rules as `PestoChip`. Collection chips ("All" and every user collection) **always display both their icon and their collection name at rest**.
  - **App chips (`PestoChip.swift`, `AppChipsRow.swift`):** When user collections are present on the command bar (`!shownPinboards.isEmpty`), app chips set `collapsesLabel = true` so collections keep their titles at rest while app chips show only their icon at rest. When there are no custom collections (`shownPinboards.isEmpty`), app chips set `collapsesLabel = false` and show their names at rest too.
  - **Layout:** the app chips are not part of the horizontally scrolling collection row. They follow the last collection chip, after a 14 pt divider and 6 pt of spacing; the collection row hugs its chips, so with room to spare the app chips sit right next to the collections and the free space falls before the search, add and window buttons. Once the collections run past the room, the row scrolls and the app chips stay in view at its end. The row scrolls the selected collection chip into view (`Motion.animation(.pestoMove)`).
  - **At rest (unselected, unhovered, unfocused):** 24 × 24 pt minimum target, 14 × 14 pt app icon, 5 pt leading and trailing padding, no label text.
  - **Expanded (pointer hover, keyboard focus, or active filter `isActive`):** 5 pt leading padding, 9 pt trailing padding, 4 pt icon-to-label gap, app name (`.caption.weight(.medium)`, `.lineLimit(1)`, `maxWidth: 200` pt), plus a bold `checkmark` icon when `isActive`.
  - **Motion:** Expands and collapses with `Motion.animation(.pestoQuick)` (0.15 s ease-out; instant when Reduce Motion is on).
  - **Accessibility & help:** `accessibilityLabel` is always the app name (`accessibilityValue` `"selected"` when active); tooltip is `"Show clips from <App>"` when inactive and `"Showing clips from <App>, click to remove"` when active.

- **On the website (`Shelf.astro`, `src/styles/home.css`, `src/lib/shelf-demo.ts`):**
  - Collection chips ("All", "Pesto night", "Recipes") always show their icon and title (`chip.label`), while each app chip carries `.chip--app` and wraps its text in `<span class="chip-label"><span>{chip.label}</span></span>`.
  - **At rest:** `.chip` has `flex: none` so chips never shrink below their expanded label width in horizontal scroll rows on mobile; `.chip--app` sets `padding-inline: 0.625rem` and `gap: 0`; `.chip-label` uses `display: inline-grid; grid-template-columns: 0fr; overflow: hidden` (`min-width: 0` on the inner span).
  - **Expanded (`.chip--app:is(:hover, :has(input:focus-visible, :checked))`):** `padding-inline-end: 0.875rem`, `gap: 0.375rem`, and `.chip-label` opens to `grid-template-columns: 1fr`.
  - **Motion:** Under `@media (prefers-reduced-motion: no-preference)`, `grid-template-columns`, `gap`, and `padding` transition over `var(--dur-quick) ease-out`.
  - **Intentional differences from the app:** The website shelf uses radio inputs (single-selection CSS demo, no checkmark glyph) and keeps neutral outlined pill styling rather than the app's tinted fills. Each `.chip--app` keeps `title={chip.label}` and `aria-label={chip.name}` on its radio input.

### Collection chip drag reorder (D3 — app only)

- **In the app (`PinboardChipView.swift`, `CommandBarView.swift`, `CollectionReorder.swift`):**
  - **Source chip while dragging:** Stays in its original slot at `0.35` opacity (`isBeingDragged`). Neighboring chips do not slide and the row width does not change.
  - **Insertion bar:** A `2 × 20` pt `RoundedRectangle(cornerRadius: 1)` in `pestoAccent`, centered in the 8 pt gap between chips, marks where the drop will land (`CollectionReorder.insertionBar`). Hidden when dropping at the pointer's current position would not change the order. Fades in with `Motion.animation(.pestoQuick)`.
  - **Drag preview:** `Color.opaqueSurface` capsule with a 1 pt `pestoAccent` border, `0.9` opacity, `1.04` scale (`1.0` under Reduce Motion), and shadow (`radius: 14, y: 6`, 28% black).
- **On the website:** Not replicated (collection chips on the marketing shelf are static filter radios, not draggable).

## Part 4: the search rows (filter groups)

Filter groups, in order: Kind, Format, When, From, Other.

- **In the app (`CommandBarView.swift`, ADR 0023):** Kind is any of six kind chips. Format is one menu chip (Markdown, JSON and the languages in the history) that reads Any until one is chosen, then its name (ADR 0025). When is **Today** and **Yesterday** chips plus a **More** menu chip (Any Time, Last 7 and 30 Days, the last hours, a day). From is one menu chip listing every app that reads Any app until one is chosen, then its name. Other holds Sensitive, and Other Devices and Hidden when they apply. The top row (collections, then the apps clips came from) shows the frontmost app and three recent ones: four app chips.
- **On the website (`Shelf.astro`, `src/lib/shelf-demo.ts`):** the same five groups in the same order (`filterGroups`), pinned by `tests/shelf-filter.test.ts` and `tests/shelf-spec.test.ts`, which read the line above. Format, More and From are `<details>` menus with no script that open upward from the docked shelf; Today and Yesterday are radio chips (the menu's Any Time clears them). The sample clips are all from the last two days, so Last 7 and 30 Days leave them all. Four app chips on the top row. **Intentional differences:** a menu stays open until its chip is pressed again (no script to close it); From is a plain list without the clip counts; Format lists only the formats the sample clips have.
- **Changing the groups:** edit the line above, `CommandBarView.swift` and the site's `filterGroups` together; `CardSpecDriftTests` fails for the app and the site's test fails for the site.

