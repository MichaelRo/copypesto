# 0077. A picture shows only after its verdict, and a browser's GIF is fetched after it

Status: Accepted (owner, 2026-11-26, backlog triage)

Amends ADR 0006's pending-clip bullet for pictures. The rest of ADR 0006 stands.

## Context
- ADR 0006 says a pending clip is covered by an opaque "Checking" surface and does not decode its picture. Since #125
  (card-first screenshot ingest) the Mac excluded pictures from that cover, so a picture's thumbnail was drawn while
  the on-device screener was still deciding: an explicit picture could show for the few hundred milliseconds before
  its verdict. A hosted test reproduced it.
- iOS kept pictures covered while the content filter is on, but drew a well, a shimmer, a spinner and "Checking
  image…" for them, and the card still decoded the picture under the cover (and under the content filter's blur).
- A GIF copied in a browser arrives as a still and its address (`RemoteGIFFetcher`). The GIF was fetched at the same
  time as the still was screened, and the GIF itself was never screened.

## Decision
- **One rule, in Core**: `CardConcealment.waitsForVerdict(type:analysisPending:nsfwMode:)`. A pending text always
  waits; a pending picture waits only while the content filter is on (`NSFWMode.detectsContent`), because with it off
  nothing in the verdict could hide the picture. The Mac card and iOS's `SecretReveal` both use it.
- **What a waiting picture shows**: the quiet picture placeholder, the same one a picture shows while it loads (a faint
  ground and the `photo` symbol, no words, no spinner), on both platforms. A large text keeps the "Checking" surface.
- **No pixels under a cover**: a waiting picture is not decoded for its card on the Mac (`pictureWaitsForVerdict`), and
  an iOS card that is covered for any reason loads no picture and lets go of the one it held (`CardMediaState`). The
  thumbnail prewarm at ingest stays: it fills a memory cache and draws nothing.
- **Check, then fetch**: the browser's GIF is fetched only after the still's verdict. When the still passed, the GIF
  is screened before it replaces the still. A flagged still or GIF still gets its GIF, so Show plays it, and the clip
  stays flagged. A verdict only adds a flag: `finishAnalysis` keeps one the GIF set.

## Consequences
- With the content filter on (the default), a copied picture's card appears at once as the placeholder and the picture
  replaces it when the screener answers, a fraction of a second later; Quick Look, the hover card, AI actions and drag
  wait for it as for any covered card. With the filter set to Show, a picture shows at once, as before.
- A browser GIF arrives a screening later than before, and costs one more screening when its still passed.
- When the still passes, the card shows it while the GIF is fetched; if the model then flags the GIF, the card turns to
  the content filter's blur. The GIF's frames are never drawn unflagged: the GIF and its flag are stored in one save.
- Showing a covered iPhone card decodes its picture then, at the clip's current size, so a GIF that arrived while the
  card was covered plays after Show.

## Docs affected
- `decisions/README.md`
- `decisions/0006-the-capture-pipeline.md`: unchanged (accepted). This ADR supersedes its pending-picture bullet.
- `Sources/Core/Storage/CLAUDE.md`, `docs/design/ios-library.md`
