# 0027. The shelf's offers are one capsule family, No results gives a next step, and a click hints at the double click

Status: Accepted

Relates to [0008](0008-undo-keeps-sealed-snapshots-in-memory.md), [0009](0009-the-shelf-and-paste.md) (single click focuses, double click pastes) and [0014](0014-shelf-suggestions.md). Nothing about storage, sync or the network changes.

## Context
The shelf offered three things in three looks: the Suggestion as a heavy full-width band, the Undo offer as a 30 pt capsule, the import offer as a top band, and the selection bar as a second capsule. A search with no match said "No results" and left the person to work out which filter was in the way. Once clips exist nothing says that a single click only selects.

## Decision
- **`ShelfBannerCapsule`** (one message, a primary button, an optional secondary one and an optional dismiss) is the one look for the Suggestion, the Undo offer and the import offer. Its glass, border and shadow are `ShelfCapsuleChrome`, which the selection bar uses as well. The capsule is 30 pt tall and floats in the band under the cards at `SelectionActionBar.bottomInset`, so `ShelfHeight`, `CardLayout` and the geometry tests are unchanged. The import offer keeps its place above the cards in the same 36 pt row (30 pt capsule and 3 pt above and below). Identifiers, decline and accept, the ring and the ghost keycap are untouched. The Suggestion's wording is unchanged: the longest line is about 100 characters and a capsule has the shelf's width; a narrower one truncates the message with a tooltip and the full text for VoiceOver.
- **Verdict on the "shelf banner architecture" backlog item:** the status banners (storage, Accessibility, errors) are not offers and stay full-width bands that keep their place. Offers are capsules. The selection bar joins the family by look (the shared chrome) but not by component: it holds a live count, a hint that drops out and icon-only fallbacks, which a message-and-buttons component would only get in the way of.
- **No results** is decided by `NoResultsAdvice` in Core. With a kind, date, app, Sensitive, Other Devices or Hidden filter on, it names them and offers **Clear Filters** (the chips go, the text stays). With none on it keeps the 500-character sentence and offers **Clear Search**. Return in the search field keeps saving the query to the search history as before. The keyboard route is Tab: the button is the last stop after the filter chips (Shift-Tab from the field reaches it first), drawn with the same ring, and Return on it clears; VoiceOver hears the name and then "Filters cleared" or "Search cleared". No new shortcut.
- **The click hint** ("Return or a double-click pastes.") is `ClickHintPolicy` in Core: shown after a single click that only focuses, once the double-click interval has passed without a second click, for 4 seconds, at most three times per Mac (a showing counts when the hint is actually drawn, once per appearance; a second click while it is up does not count or restart it), never after the person has pasted by double click. The counts are `Setting.clickHintShownCount` and `Setting.doubleClickPasted`, this Mac's own state, not carried by a backup. It sits in the bottom band when no offer is there, takes no focus or clicks, and fades through `Motion` (not at all under Reduce Motion).

## Consequences
- Pictures of the shelf with an offer, the selection bar and the empty search must be retaken, and the website demo follows separately.
- `ShelfClickHintUITests` and `NoResultsAdviceUITests` cover the button and the hint's first appearance; they were written and not run (the second presses the button with Shift-Tab and Return). The hint's timing and fade are checked by hand.

## Docs affected
- `docs/guide/using-pesto.md` (No results, the click hint)
- `decisions/README.md` (this record in the table)
