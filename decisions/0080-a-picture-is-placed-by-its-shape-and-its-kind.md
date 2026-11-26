# 0080. A picture is placed by its shape and its kind, and keeps the card's foot

Status: Accepted (owner, 2026-11-26, backlog: picture card layout and bottom edge)

Supersedes ADR 0041's placement of a fitted picture and its absolute ranges. ADR 0041's reason (a crop must not lose
the words of a boarding pass) and its blurred, darkened backdrop stand. ADR 0044 (facts on pills, no scrim) and ADR
0068 (no foot glow on a picture) stand.

## Context
- ADR 0041 fills a picture whose width over height is 0.8 to 1.35 (a GIF 0.55 to 1.85) and fits anything else. A fitted
  picture was shrunk into the card less a fixed band for the line of facts: 36 points on the Mac, 30 on iOS, 28 on the
  keyboard, none on a widget. A phone screenshot, the most common tall picture, lost 22% of its height (and about a
  third of its area) to that band, although the pills that sit there carry their own ground.
- The surfaces had drifted: the Mac used the still range for a GIF; the Mac took the shape from the decoded thumbnail
  and iOS from the stored pixel size; the keyboard card (150 × 88) used ranges drawn for a square-ish card, so a square
  photo lost 41% of itself there.
- A near-square screen capture filled and lost up to 29% of its edges, where its words are. A 32-pixel icon filled the
  card and was stretched into a blur. A receipt (0.3) stood as a sliver a quarter of the card wide.
- A Sonnet critic (UI/UX brief, 2026-11-26) argued against letting the pills cover a whole fitted picture's bottom,
  for top anchoring of tall pictures, and for ranges per surface; those points are taken below. Its proposals that
  need new stored facts (camera EXIF, real transparency) are left for later.

## Decision
- **One rule, in Core** (`PictureFit.decide`, `PictureFrame.fitted`, `ScreenCaptureApps`), used by the Mac shelf, the
  iOS library, the keyboard and AutoFill card, and both platforms' widgets. The shape is the stored pixel size when the
  clip has one, the thumbnail's otherwise.
- **Ranges are relative to the card's own shape.** ADR 0041's ranges were drawn for the Mac's Medium card (1.125):
  a picture fills when its aspect over the card's is in 0.71 to 1.2 (a GIF 0.49 to 1.64). On that card the numbers are
  unchanged; the wide keyboard card now fills a 16:9 photo and fits a square one.
- **A screen capture** (source app `com.apple.screencaptureui`, `com.apple.Screenshot`, CleanShot X or Shottr, wherever
  the clip was synced to) fills only when filling crops a tenth of it or less; otherwise it is shown whole.
- **A very tall picture** (under 0.4 at the reference shape: a receipt, a whole web page) fills from its top, which is
  what names it. A phone screenshot (0.46) is still shown whole.
- **A picture smaller than the card** (its longer side in pixels under the card's shorter side in points) is never
  filled, and is drawn at most twice its pixel size; 64 pixels or fewer are drawn with hard edges (an icon, pixel art).
- **A fitted picture keeps the card's foot without giving up its height**: it fits the card less 18 points; of the
  height left over, up to the facts' band (and a title's) goes under it, the rest is shared above and below. A tall
  picture runs from the top to 18 points above the foot, so the pills cover at most their own lower half of it; a wide
  one clears the facts. A SwiftUI `Layout` (`PictureFrameLayout`) places it, so no surface reads its own geometry.
- **A focused or pointed picture card on the Mac says its dimensions** (`1920 × 1080`) on its line, ahead of the app's
  name when the line is short (the app's icon stays). iOS, the keyboard and widgets have no focus and do not.
- Backdrops: blur 14 and 35% black on the Mac and iOS library (iOS was 12); the keyboard keeps its stretched small copy
  and the widget its own, for memory.

## Consequences
- A phone screenshot on the Mac's Medium card is 142 points tall instead of 124 (about 31% more area); on every
  surface the facts stay on their pills and stay legible (`PictureScrim` is unchanged).
- A wide GIF (1.5) on the Mac now fills its card, as it already did on iOS.
- A square screen capture shows its edges; a receipt shows its header; a small icon is shown at a size that says it is
  small.
- Capture detection by source app misses a screenshot pasted from a browser or a chat; it is then treated as a picture,
  as before. Camera EXIF and real transparency (a logo over a blurred copy of itself) are possible later signals; they
  would need a stored fact per clip.
- `make pictures` and the website's demo shelf show the new placement.

## Docs affected
- `decisions/README.md`; `decisions/0041-a-picture-fills-the-card-only-near-its-shape.md` (accepted, unchanged; superseded here)
- `docs/design/ios-library.md` (Picture row), `docs/design/website-shelf-spec.md` (Picture row, a fitted picture row)
