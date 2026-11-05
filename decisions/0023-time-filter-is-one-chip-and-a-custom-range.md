# 0023. The When filter keeps Today and Yesterday as chips and puts the rest in one menu, and a range can be any span Ask can read

Status: Accepted

Relates to [0014](0014-shelf-suggestions.md) only through the bar; the search chips and Ask Pesto are older. Nothing about storage, sync or the network changes.

## Context
The search filter bar showed 19 to 21 chips, five of them for time (Any time, Today, Yesterday, 7d, 30d), and was always longer than the shelf, so it invited scrolling. The five ranges were also all there was: no single day, no last few hours, no range. Ask Pesto already turns a sentence into filters but could only name those five.

## Decision
- `SearchDateFilter` (now in `Core/Model`, so `Search` does not depend on `Storage`) gains `.custom(DateInterval)` for a day or a range of days, from its start up to but not including its end, and `.last(TimeInterval)`, a rolling span back from now that is worked out each time the filter is applied, so a clip copied after "Last 3 hours" was chosen is still in it. `AskDateRange` is the same type, so what Ask reads and what the bar holds cannot drift apart. Presets keep their meaning.
- **When keeps Today and Yesterday as one-click chips** (choosing the one in force again clears it) **and one More chip** with a native pop-up menu: Any Time, Last 7 Days, Last 30 Days, Last Hour, Last 3 Hours, Last 12 Hours and a day from the last two weeks. The chip names the range in force. Tab reaches it and Return opens the menu. It is a `PopUpMenuButton`, not a SwiftUI `Menu`, which exposes no press action on macOS 27.
- **From and Format are one labelled menu chip each**, the same pattern as More. From lists every app with its clip count and reads "From" until one is chosen, then the app's name (or the first and how many more). Format lists Markdown, JSON and the languages in the history with counts. The three app chips and the Markdown and JSON chips are gone: the shelf's app chips row stays the quick way to an app. Choosing a format puts `@name` in the search field, which replaces what was typed, as the old chips did. A language matches by its first letters, and exactly when what is typed is a whole name in the history (`@java` is Java only; `@javas` is JavaScript). Tab reaches both and Return opens the menu.
- **Any other date is a sentence for Ask**: "last 3 hours", "30 minutes ago", "on Nov 3", "3 Nov", "2026-11-03", "last Thursday", "between Nov 1 and Nov 3". `DateRangeParser` reads them with the rules, so they work with Apple Intelligence off; the model's range is still overridden by the rules. A day with no year is the most recent such day, never a future one. A weekday is its most recent past occurrence. A month name alone ("may budget") stays a keyword.

## Consequences
- The bar is shorter, 12 chips or fewer instead of 19 to 21: six kinds, Format, Today, Yesterday, More, From, and one to three of Sensitive, Other Devices and Hidden. It is still scrollable for the rare wide case.
- There is no calendar picker. A DatePicker popover from a non-activating panel is untested in this app (compare the hover card, ADR 0009), so arbitrary dates go through Ask for now; adding a picker is a follow-up that needs a hand check on a real shelf.
- Seconds are not offered: a clip is never copied so precisely that a range of seconds helps.
- The pictures of the shelf with search open, and the teaser frames that show the filter bar, need to be retaken.

## Docs affected
- `docs/guide/using-pesto.md` (the filter chips, Ask's dates)
- `decisions/README.md` (this record in the table)
