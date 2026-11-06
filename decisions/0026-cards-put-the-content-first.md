# 0026. Cards put the content first: a picture, a color, short text and a link's host are the loudest thing on their card

Status: Accepted; the sizes of short text and of a link's host are superseded by 0031

Relates to `docs/design/card-typography.md` (the header stays the quiet band for every card that keeps one). Nothing about storage, encryption, sync or the network changes.

## Context
Every card was a header band (app tile, the name of the kind of clip, age), a body and a footer. A picture sat in a small window between two bars, a color was a swatch with its hex in the footer, a one-line note or a link looked like the first line of a long text. For a person scanning the shelf for "that screenshot" or "that color", the chrome was louder than the clip.

## Decision
- **`CardTreatment` (Core/Runtime) decides, pure and tested; the views only draw it.** It reads the type, the text, whether a picture is loaded (its aspect ratio, whether it is animated), whether a link's preview picture is shown, a color's parsed value, the color scheme, and one flag, `isConcealed`. Concealed (hidden, covered for a screen share, content-filter blur, masked or sensitive, not yet screened, title being renamed) is always `.standard`, the card as it was (ADR 0003).
- **Picture and GIF:** the picture fills the card (the cached thumbnail, no new decode); the header floats over it on a black scrim and shows the app's name and the age in white, not "Image" or "GIF". The shortcut number is a small outlined pill at the bottom left, with a GIF pill beside it. A picture whose aspect ratio is outside 0.6 to 2.0 (a phone screenshot, an ultrawide banner) is fitted below the header instead of cropped to a thin slice (`PictureFit`). A GIF moves exactly as before (`AnimatedImageView`, `playsAnimations`).
- **Scrim contrast is arithmetic, not taste** (`PictureScrim`): black at 60% across the whole header band, fading over 40 pt below it; white text at 100% (name) and 85% (age) over the scrim, and white text at 100% on the 60% dark pill ground for the shortcut number, GIF, paste count, tags and collection badge, give at least 4.5:1 over a white picture, the worst case (`PictureScrimTests`). Nothing on a picture is drawn without one of those two grounds.
- **Color:** the card is the color; the hex is set at 26 pt semibold (15 pt for a longer `rgba()` form) bottom left; black or white ink by contrast (`CardInk`), at full strength for the header name and age, the hex, the pill and the badge: 4.5:1 or better on any fill, mid-luminance ones included (`CardInkTests`).
- **Short text** (one line, at most 48 characters, not code, not a lone glyph): 24 pt semibold up to 16 characters, 20 up to 32, 17 up to 48, scaled with the card size like all body text, wrapping on at most three lines (fewer on a small card, `largeTextLineLimit`). Fixed sizes by length: no `minimumScaleFactor`, no measuring.
- **A plain link** (no preview picture, no title, no site name, no icon) leads with its real host, 22, 17 or 15 pt by length (wraps after dots; an IPv6 host keeps its brackets), then the port and path in the quiet color, cut at 80 characters. The query and the fragment are never shown, because a magic-link or reset token lives there and the old card showed no address at all. The host is read with `URLComponents`; user info is dropped (`paypal.com@evil.example` shows `evil.example`) and a page's own `ogSiteName` is never used. A link with metadata keeps its rich body (title, site name, icon), and one whose picture is shown keeps its picture body.
- **Unchanged:** code, long and multi-line text, every file card (PDF and video previews stay 44 pt, live QuickLook requests), a lone glyph, anything concealed, collection badges, selection and focus rings, hover, drag, the context menu. A card is still one accessibility element with its old label and value.

## Consequences
- **Cost:** no new decode, no blur, no offscreen pass, no `GeometryReader`, no measuring. A picture card swaps the header's wash and the body's frame for one image, one fixed-height gradient and two small pills; the decision runs per `body` and for text and links costs one pass over at most 500 characters (the single-glyph check already did this). To be measured by the owner: `make bench-scroll`, `make bench-latency`, the memory budget.
- The thumbnail is 480 px on its longest side (made for the old window). A 16:9 picture filled into the Medium card on a Retina display is scaled up about 1.3 times and a little soft; raising the size costs memory per cached thumbnail and is left to a measurement.
- A plain link shows a host and a path where it showed only the kind word; a link with metadata is unchanged. The hover card shows a link's title and site name, not its icon, as before.
- The text of a link's host and a short text's size are remembered per clip text (`StringMemo`, capped at 4,000 entries), so a card redrawn many times parses once.
- The website's demo shelf and the film follow in separate changes: `docs/design/website-shelf-spec.md` has the values. The pictures of the shelf (`make pictures`) and the teaser frames need to be retaken.

## Docs affected
- `docs/design/website-shelf-spec.md` (the new treatments and values)
- `decisions/README.md` (this record in the table)
