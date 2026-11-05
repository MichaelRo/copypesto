# 0023. The When filter is one chip with a menu, and a range can be any span Ask can read

Status: Accepted

Relates to [0014](0014-shelf-suggestions.md) only through the bar; the search chips and Ask Pesto are older. Nothing about storage, sync or the network changes.

## Context
The search filter bar showed 19 to 21 chips, five of them for time (Any time, Today, Yesterday, 7d, 30d), and was always longer than the shelf, so it invited scrolling. The five ranges were also all there was: no single day, no last few hours, no range. Ask Pesto already turns a sentence into filters but could only name those five.

## Decision
- `SearchDateFilter` gains `.custom(DateInterval)`: from its start, up to but not including its end. `AskDateRange` is the same type, so what Ask reads and what the bar holds cannot drift apart. Presets keep their meaning.
- **When is one chip.** It names the range in force ("Any time", "Today", "Last 3 hours", "Nov 3", "Nov 1 – Nov 3"). A click opens a menu: the presets, the last hour, 3 hours and 12 hours, and a day from the last two weeks. The keyboard still reaches it with Tab, and Return steps through the presets.
- **From shows the three most copied apps**, and any further app that is in use so it can be switched off.
- **Any other date is a sentence for Ask**: "last 3 hours", "30 minutes ago", "on Nov 3", "3 Nov", "2026-11-03", "last Thursday", "between Nov 1 and Nov 3". `DateRangeParser` reads them with the rules, so they work with Apple Intelligence off; the model's range is still overridden by the rules. A day with no year is the most recent such day, never a future one. A weekday is its most recent past occurrence. A month name alone ("may budget") stays a keyword.
- A relative range ("last 3 hours") is fixed when it is chosen: a clip copied afterwards is not in it until the range is chosen again.

## Consequences
- The bar is shorter, 13 to 15 chips instead of 19 to 21. It is still scrollable for the rare wide case.
- There is no calendar picker. A DatePicker popover from a non-activating panel is untested in this app (compare the hover card, ADR 0009), so arbitrary dates go through Ask for now; adding a picker is a follow-up that needs a hand check on a real shelf.
- Seconds are not offered: a clip is never copied so precisely that a range of seconds helps.
- The pictures of the shelf with search open, and the teaser frames that show the filter bar, need to be retaken.

## Docs affected
- `docs/guide/using-pesto.md` (the filter chips, Ask's dates)
- `decisions/README.md` (this record in the table)
