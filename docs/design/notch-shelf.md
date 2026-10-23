# The top shelf may grow from the notch on open, and draws nothing while idle

A proposal, not built. It needs a prototype on a notched MacBook before it is decided (tracked as an issue).

## Context
ADR 0006 put the shelf at the top, below the menu bar and below the notch band on a Mac that has one. On a notched Mac
the shelf then sits next to the notch without touching it. The question was whether the shelf can belong to the notch
(a "Dynamic Island" opening), and whether something should also be drawn while the shelf is closed.

What the system gives (public AppKit API since macOS 12; `safeAreaInsets.top` is already used by `ShelfPosition`, the two auxiliary areas are not yet used anywhere in Pesto):
`NSScreen.safeAreaInsets.top` is the notch's height, and `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the two
menu-bar areas on either side of it, so the notch's width is the screen width minus the two. The wings hold the person's
own menu-bar items (status icons, clocks, other menu-bar apps).

## Decision
1. **Open only.** On a screen with a notch, with the shelf at Top, opening the shelf may play a short transition that
   starts at the notch: a black neck the width of the notch drops below the menu bar line, then the glass widens from
   its middle to the full width. Closing plays it in reverse, about 20% faster. Nothing is drawn while the shelf is
   closed.
2. **Clips stay in one band below the menu bar.** No clip is drawn in the wings, so no menu-bar item is ever covered.
   The neck carries only a search pill while the shelf is open.
3. **Geometry comes from the screen**, never from constants: the notch rect is a pure function of the three values above
   (`ShelfPosition.Screen` gains `auxiliaryTopLeftWidth` and `auxiliaryTopRightWidth`), unit tested like
   `ShelfPosition.frame`. A screen without a notch has no neck and keeps today's slide.
4. **Reduce Motion** replaces the growth with a 120 ms fade, through `Motion.animation`.
5. **Hidden until proven:** the first build sits behind a hidden default (no Settings row), so a bad notch case on
   someone's Mac cannot reach people through the normal setting.

| Part | Starting value (tune on a real notch) |
|---|---|
| Neck width | the notch's width |
| Neck height below the menu bar line | 46 pt |
| Neck bottom corners | 18 pt, continuous |
| Concave fillets where the neck meets the shelf top | 10 pt |
| Shelf bottom corners | 16 pt, as the Settings preview draws them |
| Open | about 280 ms: neck 0 to 46 pt, then width from the neck's to full; spring, response 0.35, damping 0.86 (`Motion.pestoMove`) |
| Close | the same path backwards, 0.8 of the time |

```
menu bar    [ wing ........ ][ NOTCH ][ ........ wing ]     wings: the person's items, never covered
shelf top   ----------------/  neck   \----------------     concave fillets, 10 pt
            [ clip ][ clip ][ search ][ clip ][ clip ]      one band, below the menu bar line
            ----------------------------------------------
```

SwiftUI and AppKit shape of it, for the prototype: the shelf stays one `OverlayPanel` at the frame `ShelfPosition.frame`
returns. The neck and fillets are a `NotchNeckShape` (`Shape`, `UnevenRoundedRectangle` radii plus two concave arcs)
drawn at the top of `OverlayRootView`, black, inside the panel and not in a second window. The growth animates the
mask or clip width of the glass inside the panel; the panel's frame and its layer transform do not change, so the
invariants in `Features/Overlay/CLAUDE.md` (explicit `toValue`, `.forwards`, `removeAnimation` before `orderOut`) are
untouched.

## Considered and not chosen
- **An idle status curve hugging the notch.** It needs a window on every notched screen all day, which competes with
  the menu-bar items, costs CPU against the 0.5% budget, and needs a pointer monitor to react to a hover. The only
  global listeners Pesto has act on ⌘C, ⌘V and Esc (`KeyListenerFilterTests`); a pointer monitor would end that.
- **Clips in the wings.** They are the person's menu-bar space, and the area is a different size on every Mac and with
  every menu-bar app installed.
- **A neck in the shelf's glass.** The notch is black; a glass neck would show a seam where the two meet. The neck is
  black and the shelf below it is glass, so the seam is a fillet and not an edge.
- **Making this the Top position's only look.** A Mac without a notch, an external display and a notched Mac with the
  menu bar set to hide all need the plain top shelf, which stays.

## Docs affected
`docs/guide/settings.md` (only when the setting becomes visible), `docs/testing.md` (hand checks), `CHANGELOG.md` (on
acceptance), `decisions/README.md`.

## Consequences
Nothing changes today. A prototype needs a notched Mac and these hand checks: a 14-inch and a 16-inch screen, an
external display next to a notched one, a full-screen app (the menu bar hides and so does the notch band), an
auto-hidden menu bar, Stage Manager, a crowded menu bar, and VoiceOver's focus order into the shelf. The decision is
accepted only after those pass, or dropped.

## How we got here
Michael's design brief of 2026-10-18 asked whether the top shelf can embrace the notch. The canvas "Pesto nav, tiles,
icon, notch" shows the four states. The idle curve was refused first because of the listener rule above.
