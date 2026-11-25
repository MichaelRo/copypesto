# 0070. The Find bar has three zones in the command block's one row

Status: Accepted (owner pick, design board 1b, 2026-11-25)

Amends ADR 0023 (where the When filter's ranges live) and the Find bar of `587bc19b` (a 190 to 260 pt field at the
left). ADR 0016 (arrows move between results), ADR 0014 (suggestions never move cards) and the 46 pt command block
stand. (0066 to 0069 are taken by records on other branches.)

## Context
After `587bc19b` the Find bar moved nothing, but its field was a small box at the left of a 1,500 pt shelf with 13 pt
type, and the filters crowded it. The owner wanted a bigger, centered field, every filter in view and one click away,
and the scope strip (collections and apps) still reachable, with no card moving and the bottom capsules intact.

## Decision
- **One 28 pt row** in the same block as the chip strip: 10 pt above, 8 below (`ShelfHeight.commandTopInset`,
  `commandRowHeight`, `commandBottomInset`), in both modes, so opening Find moves nothing
  (`ShelfGeometryTests.test_openingFind_movesNoCard`).
- **Three zones**: on the left, where you search (the collections, then the apps), scrolling; in the middle, the field
  (`ShelfHeight.searchFieldWidth`: about a third of the shelf, 320 to 480 pt) in title-3 type, with Ask and Cancel
  beside it; on the right, every filter as a one-click chip, scrolling. Each strip fades where it runs out of room.
- **A chosen filter is a token in the field** (with a press to take it off), so it stays in view when its chip has
  scrolled away.
- **The ranges beyond Today and Yesterday** stay behind one Date chip (they were "More").
- The floating window's copy-only Return in search now copies (`ShelfPaste.copy`), as its cards do; it took the
  shelf's paste route before (found mapping every Return, `docs/design/search-and-return.md`).

## Consequences
- The field's type and the row are larger; at a large system text size the row grows and the panel with it
  (`AppState.shelfTopOverflow`), as before.
- Suggesting a filter as one types ("tod" for Today), drawn on the board, is not built yet: backlog.
- The website's shelf demo follows (backlog), and the pictures of the shelf with Find open are retaken at the next
  `make pictures`.

## Docs affected
- `docs/design/website-shelf-spec.md` (Part 4), `Sources/Features/Overlay/CLAUDE.md`, `decisions/README.md`
