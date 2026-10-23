# Card whitespace and line breaks: show the text, count the lines, add no glyphs

**Design only: needs your
eye before any SwiftUI changes.**

## What is true today
- A text card draws the first 500 characters of the clip with `lineLimit` 3, 5 or 6 by card size
  (`ClipboardCard+Parts.swift`, `cardBody`). Newlines are kept; nothing else is done to the text for display.
- Ingest turns `\r\n` and `\r` into `\n` in the stored clip (`ClipboardRules.normalizeLineEndings`, on by default).
  Nothing handles U+2028, U+2029, a vertical tab or a form feed, all of which Swift's `Character.isNewline` counts as a
  line break.
- Leading blank lines push the text down the card, and a run of blank lines spends the line limit on nothing, so a clip
  copied from a web page can show a header, a gap and one line. A text of only whitespace shows the type symbol.
- The footer says "N characters". No card says how many lines a clip has.

## Status
Implemented (2026-10-21): `CardPreviewText` (`display`, `paragraphs`, `footerLineCount`) in Core, `ParagraphColumn` for the
body, the footer "N characters · M lines". Choices the doc left open: the body's height budget is the line limit times the
line height (`CardLayout.textBlockHeight`), so a gap costs its 6 pt and a card of paragraphs shows no more lines than a card
of one; the paragraph that crosses the budget is cut by `Text` at a whole line with an ellipsis. The footer joins the two
existing plural strings ("64 characters · 8 lines"), and falls back to characters only, then to nothing, as the card
narrows. The website values are in `website-shelf-spec.md`.

## Skeptical reading of the item
"Subtle visual cues for multiline spacing and soft returns" invites a glyph at every break. That is the clutter the item
warns about (rejected on the canvas: it reads like an editor with invisibles on). A person looking at a card needs three
things: the text starts at the top, paragraphs still look like paragraphs, and some sign that the clip has more lines than
fit. Two of the three are about what is drawn, not about marking it. Nothing here touches the stored clip, the search
text, or what a paste writes: this is display only.

## Proposal
1. **Compact for display** (a pure function in Core, `CardPreviewText.display(_:)`, tested like `TextLines`):
   - every Unicode line break (`isNewline`) becomes `\n`, so U+2028 and a vertical tab draw as the break they are;
   - leading blank lines and leading spaces of the first line are dropped;
   - trailing whitespace is dropped;
   - a run of two or more blank lines becomes one blank line.
2. **A blank line draws as a slim gap**, not a full text line: 6 pt, with a dotted rule at 50% of the quiet color (the
   canvas's proposed card). The gap keeps the paragraph, and the line limit counts it as half a line, so the card shows
   more words. This needs the body to be drawn as paragraphs (one `Text` per paragraph in a `VStack`, spacing 6) instead
   of one `Text`; the cost is a little layout work for a card that shows at most 500 characters.
3. **The footer carries the line count**: "64 characters · 8 lines". Only when the clip has more than one line and the
   whole text is in the preview (`textLength` ≤ the preview's length), as the hover card does for code; otherwise the
   footer stays "N characters", because a count of the first 500 characters would be wrong. It uses `TextLines`
   (already in Core from the snippet badge).
4. **No glyph at a break and no marker for trailing whitespace.** Whitespace-only clips keep the placeholder.

## Alternatives rejected
- A return glyph at each break (canvas, right): noise on every multiline clip, which is most of them.
- Showing blank lines and the soft-return U+2028 differently from hard returns: a person cannot tell the difference in
  the app they paste into, so telling them on the card is a distinction with no use.
- Collapsing every blank line (single spacing): destroys the paragraphs that make code and prose readable.
- Changing the stored clip: ingest rules are the person's setting, and a paste must give back what was copied.

## What a change would touch
`Sources/Core/Model/CardPreviewText.swift` and its tests first; `ClipboardCard+Parts.swift` (`cardBody`,
`characterCountText`) next; `TypographyTests` counts `.font(.system(size:` per file; the card snapshots are stale and
must be re-recorded (see `card-typography.md`). The line-limit formula must count a gap as half a line.

## Not verified
Whether SwiftUI's `Text` already draws U+2028 as a line break. The function above makes it moot, but the compaction
would still be needed for the leading and repeated blank lines.

## Website (`Shelf.astro`, spec only)
`.sc-body` has no `white-space` rule, so the site's cards collapse every newline and show a different card than the
app. Add `white-space: pre-line` to `.sc-body`; `-webkit-line-clamp` still clamps rendered lines. The compaction does
not need to be mirrored: the site's sample text is written by hand and has no stray blank lines. If a sample gains a
paragraph break, give it `.sc-gap { display: block; height: 0.375rem }` instead of an empty line.
