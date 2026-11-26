# 0076. A widget orders a collection from its newest 60 members; on iOS Match App Icon starts off

Status: Accepted (owner, 2026-11-26, backlog triage)

Amends ADR 0060's plain-collection window and ADR 0069's Match App Icon switch on iOS. The rest of both stands.

## Context
- ADR 0060 orders a plain collection on a widget from its newest 300 members (`collectionScanLimit`) and turned down
  60 because older hand-placed clips would drop off. Every rewrite opens the sealed metadata of those members for
  `CollectionOrder`, so with 24 collections a rewrite took about 180 ms (debug build). That cost comes back on every
  change to the history, in the app and against WidgetKit's timeline budget, to choose eight clips per collection.
- The keyboard and AutoFill set (`QuickInsertSelection`) used the same widget constants for its collections, so a
  change to the widget would also have changed the keyboard, which carries up to 30 clips per collection.
- ADR 0069 made the icon follow the theme with one switch, on by default. On iOS every
  `setAlternateIconName` call shows a system alert that the app cannot suppress. With the switch on by default, a
  person on Parmesan, Pine nut or Mortar who opened and closed Settings got an alert about an icon change they never
  asked for.

## Decision
- **Widget window**: `WidgetSnapshotPolicy.collectionScanLimit` is 60. A smart collection still matches among the
  newest 300 clips (`smartScanLimit`, one fetch shared by all smart collections).
- **The keyboard keeps its own window**: `QuickInsertPolicy.collectionScanLimit` and `smartScanLimit` are 300.
  `QuickInsertCollectionsTests` fails if a hand-placed member past the widget's window leaves the keyboard.
- **Match App Icon on iOS starts off** (`AppIconMatching.isOnByDefault`, the default of `Setting.matchesAppIcon`). The
  icon changes only after the person turns the switch on (it applies at once) or, with it on, when they close
  Settings. A value the person stored is kept. The Mac still starts on, because macOS changes the icon without asking.
  There is no iOS migration: no iOS release had shipped with the switch.

## Consequences
- A clip placed by hand in a plain collection but older than its newest 60 members is not on that collection's widget,
  while the library, the shelf and the keyboard still show it. Measured (debug, `WidgetSnapshotPerformanceTests`):
  24 full collections take 68.7 ms instead of about 180 ms. One collection takes 6.0 ms.
- On iOS a new install keeps the Basil icon whatever theme is chosen, until the person turns the switch on.

## Docs affected
- `decisions/README.md`
- `decisions/0060-a-widget-can-show-a-collection.md` and `0069`: unchanged (accepted). This ADR supersedes the parts
  named above.
