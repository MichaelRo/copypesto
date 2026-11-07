# 0036. The hover card's Copy Text button is as wide as its label

Status: Accepted

Nothing about the network, storage, backup or sync changes. It supersedes one clause of ADR 0034: Copy Text was "at least 84 pt wide".

## Context
Copy Text is the hover card's only button (ADR 0034). With a minimum width of 84 pt and its label pushed to the right, the wash behind it while the pointer is on it had about 22 pt of empty space on its left and 8.5 pt on its right, so the button looked off-centre and the card looked as if it had a spare margin on that side. The card's text rows sit 10 pt inside their boxes; the button was the only thing that did not.

## Decision
- **The wash is the label plus 8 pt on each side, 22 pt tall** (`HoverCardCopyButton.washInset`, `height`), with no minimum width. The label's right edge sits on the 10 pt text inset the other rows use (`trailingBleed`), as before.
- **"Copied" takes the same room, so the row grows to the left.** The "Text in the picture" caption on the left of the row has more than enough space.
- The target is 22 pt by about 69 pt, smaller than before. It is a pointer target in a window that is never key; the card offers the same action in the context menu and as a VoiceOver action.

## Consequences
- The hover card picture of a picture with text changes (`make pictures` retakes it; the website's demo card has the same button and is drawn to match in the website repo).
- `test_copyTextButton_whenAtRest_thenItsWashHugsTheLabel` measures the button against the label, so a minimum width cannot come back unnoticed.

## Docs affected
- `decisions/README.md`
- `docs/testing.md` (hand check: the hover card's Copy Text on a picture with text)
- the website's demo hover card for a picture (website repo)
