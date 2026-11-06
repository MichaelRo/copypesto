# 0031. Short text and a link's host are set in two sizes, 24 and 18 pt, with the first line at one fixed distance under the header

Status: Accepted

Supersedes the size part of ADR 0026 (the 24, 20 and 17 pt steps for short text and the 22, 17 and 15 pt steps for a link's host). Everything else in 0026 stands. Nothing about storage, encryption, sync or the network changes.

## Context
ADR 0026 set short text in three steps and a link's host in three others. A typography review found six sizes where the eye can tell two: neighbouring cards at 20 and 17 pt read as the same card set by mistake, the 15 pt host was smaller than the text it was meant to lead, and a first line sat at a different distance under the header on each step, because the gap was measured to the top of the line box and a bigger size has more space above its capitals. Card tops did not line up across a shelf.

## Decision
- **Two steps, shared by text and link hosts.** A text clip that is a single short paragraph, counted as `CardTreatment` counts it (`Character`s after `CardPreviewText.display` trims it, so an emoji, a flag or an accented letter is one):
  - up to 24 characters: 24 pt semibold, at most 2 lines;
  - 25 to 48 characters: 18 pt semibold, at most 3 lines;
  - above 48, with a line break, empty, or a lone glyph: unchanged.
- **A plain link's host** (same conditions as 0026): up to 24 characters of host 24 pt semibold, otherwise 18 pt semibold. There is no 15 pt step. The port and path stay 11 pt in the quiet color. The host stays on one line and never wraps mid-host: it shrinks with `minimumScaleFactor` down to 0.7 of its size (`LinkDisplay.hostMinimumScale`; the smallest drawn host, the 18 pt step on a Small card, is then 10.7 pt, above the 10 pt floor), and only then is cut with an ellipsis at its end. A 16-character host fits at every card width; a host near 24 characters is usually cut on a narrow card. The path takes the room the host leaves (`LinkDisplay.pathLineLimit`, up to 3 lines on a roomy card, else 2) and gives way before the host is cut. The website's demo shelf already does the same.
- **Sizes scale with the card, never with the text-size setting.** The card-size factor (`CardTextScale`, 0.85 to 1.2) still applies, so the Large card draws 28.8 and 21.6 pt. The system text-size setting no longer enlarges these two steps (the cap is the card-scaled size), because a fixed card cannot hold a larger headline; every other card text keeps its own cap. The line limit also lets the card's height budget lower the count (one line on a card too short for two).
- **The first line's capitals sit 12 pt under the header on both steps** (`CardLayout.glyphTopInset`). The body's 6 pt top padding is measured to the line box, so each step adds the difference between 12 pt and its own space above the capitals (ascender less cap height, read from the font), never negative and at most 4 pt (`CardLayout.largeTextTopPadding`); the height budget is reduced by that padding.
- Covered cards are unchanged.

## Consequences
- Two sizes are easier to tell apart and to implement on the website; the 20 pt and 17 pt cards of a shelf become 24 or 18 pt ones, so a clip of 17 to 24 characters gets larger and one of 33 to 48 is a point larger.
- 24 pt text of 17 to 24 characters wraps to a second line on a Small card more often than before; that fits (64 pt of room, two lines of 20.4 pt at 1.25 take 51).
- The cost is as in 0026: the size is still decided from the text once per clip (`StringMemo`), one extra `NSFont` metric read per body for the offset.
- Sizes under the largest system text size were checked by reasoning and a Core test over every slider width (the line limits plus the offset fit the budget), not on a Mac at the largest setting: that remains a hand check.

## Docs affected
- `docs/design/website-shelf-spec.md` (the two steps, the offset)
- `docs/testing.md` (hand check)
- `decisions/0026-cards-put-the-content-first.md` (status line)
- `decisions/README.md` (this record in the table)
