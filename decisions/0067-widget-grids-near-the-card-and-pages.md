# 0067. A widget's grid keeps the card's shape, and medium and large widgets page

Status: Accepted (owner request from field notes, 2026-11-20; WidgetKit consult 2026-11-25)

Amends ADR 0052 (how many cards each family shows) and ADR 0060 (what a collection widget can reach). Nothing about
the snapshot, its key, its bounds or what may enter it changes.

## Context
Field notes: the iPhone widget's cards had "weird dimensions", and the owner asked whether a widget could scroll, for
a collection above all. With WidgetKit's default content margins a medium widget gave three tiles about 105 × 138 pt
(0.76, tall) and a large one six about 162 × 111 pt (1.46, wide), far from the card's 10:9. WidgetKit cannot scroll:
a widget is drawn once per timeline entry and takes no gestures; a `Button` running an App Intent is the one way to
change it from the Home Screen.

## Decision
- **Grids near 10:9** (`WidgetSize.grid`): small one card filling the widget; medium two side by side (about
  144 × 138); large two by two (about 162 × 155); extra large, on iPad only, two by four (about 165 × 151). At an
  accessibility text size medium shows one, large two, extra large four.
- **Medium and large page** (`WidgetPaging`, `ShowClipPageIntent`, `WidgetPageControl`): chevrons and dots in a narrow
  column at the trailing edge of a medium widget and in a strip under a large one's grid, shown only with more than
  one page; the last page wraps to the first. Small and extra large never page. With today's snapshot (eight recent,
  six pinned, eight per collection) that is up to four pages on medium and two on large.
- **The page lives in the widget extension's own preferences** (`Setting.widgetPages`): a page number and two dates
  per family and list, never any content; the app never reads it, so the Mac needs no group container for it.
  WidgetKit gives no public id for one widget, so two widgets of the same family showing the same list page together.
- **A page goes back to the first** when a newer snapshot arrives or ten minutes after it was turned (the timeline
  carries that moment), so a widget does not stay on page three for good.

## Consequences
- Fewer cards at a glance on medium (two, was three) and large (four, was six), each larger and in the card's shape;
  the rest is one press away.
- Whether a press inside a widget is exempt from the reload budget is not documented; a device check watches for a
  page that stops turning.
- Tinted and clear Home Screen modes draw the controls with `widgetAccentable`, the dots in primary and secondary.

## Docs affected
- `docs/design/ios-library.md` (the widget section)
- `docs/testing.md` (device checks)
- `decisions/README.md`
