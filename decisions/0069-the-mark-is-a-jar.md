# 0069. The mark is a jar

Status: Accepted (owner pick, design board 6b "C1", 2026-11-25; expert panel comparison the same day)

Amends ADR 0013's icon rule ("the cards stay garlic glass"): the glass card stack becomes a jar. The rest of 0013
stands: the ground carries the theme, the mark is garlic, the P is the theme's deep accent, four themes, one icon each.
(0066 to 0068 are taken by records on other branches, so this one is 0069.)

## Context
The logo reassessment (backlog, 2026-11-20) found the card stack generic (a P on a tile, close to a competitor's), off
center, and muddy at small sizes and in tinted and clear modes, where its third card turned into a smudge. The brand
book's own metaphor is a jar: stored, sealed, local. The owner chose the jar, and asked that the menu bar decide, since
it must be clear and cohesive there. A panel (brand, Apple platform, usability) compared the two head to head: the jar
won on silhouette, small sizes and tinted and clear modes, with one risk, that a lid over a box reads as a trash can.

## Decision
- **The jar** (`design/source/icon-layers.swift`, the same geometry in `brand-art.py` and `menubar-icon.swift`): a
  garlic lid 72% as wide as the body and 11% of the canvas tall, a gap of ground (66 px at 1024, still a pixel at 20),
  and a garlic body 60% of the canvas wide with shoulders (top radius 30% of its width, base 16%) so it reads as a jar,
  not a bin. The P sits on the body. Icon Composer layers: the P, the jar body and the lid, solid, so tinted and clear
  modes keep the shape.
- **The menu bar** is the same jar as a template at 18 pt, every edge on a whole pixel at 2x, with the P cut out of the
  body; Locked, Hidden and Paused add their badge to it (`menubar-glyphs.swift`).
- **Themes** keep their grounds and deep-accent Ps (`theme-icons.py`); Mortar's ground is a step deeper so the garlic
  lid stands off it.

## Consequences
- To test with people before release (the panel's risk): a five-second test of the menu bar among six common icons,
  light and dark; under 10% should read delete, trash or archive. If it fails, push the shoulders further first.
- Every picture that shows the icon is retaken (`make pictures`), and the website's icons and favicon follow
  (`copypesto-website`, `scripts/make-icons.sh`): recorded in the backlog.

## Docs affected
- `design/README.md`, `decisions/README.md`
- README and guide pictures at the next `make pictures`
