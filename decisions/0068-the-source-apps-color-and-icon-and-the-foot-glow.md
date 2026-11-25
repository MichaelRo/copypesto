# 0068. A clip's source app reaches every device, and a card's foot glows in its color

Status: Accepted (owner picks on the design board, 2026-11-25: "foot glow", board 2b)

Amends ADR 0044, which removed the source app's color wash with the card header, and ADR 0018's sync format with two
additions an older device ignores. Encryption at rest, what syncs about a clip's content and the one-writer rule are
unchanged.

## Context
Field notes (2026-11-22): the iPhone app needs a little more life, its cards show no source app icon, and the Mac
once had a hint of color. The iPhone cannot look an app up by its bundle ID, and sync carried only the bundle ID and
the name. The design board drew three treatments; an expert panel (brand, Apple platform, color and accessibility)
proposed a fourth between the owner's two favorites, the foot glow, and the owner chose it.

## Decision
- **The color travels with the clip:** `SyncItemRecord.sourceColorHex` (optional, `#RRGGBB`). A clip that has no
  sampled color of its own adopts it.
- **The icon travels once per app:** each Mac writes `devices/<id>/apps.pestoapps` (`SyncAppCatalog`): the apps its
  newest clips came from (at most 128), each with its name, a PNG icon of at most 8 KB and its color, sealed under the
  sync key and signed by the Mac like its head, rewritten only when the list changes, read through `SyncSmallFile`.
  A new record kind was rejected: an older device refuses a segment with a kind it does not know. An iPhone resolves no
  app, so it writes no catalog; it keeps what it reads in `SourceAppCatalogStore` (an owner-only file of at most 256
  apps, emptied by Clear History). The catalog holds what the history's plain columns already say (bundle ID, name)
  plus an icon and a color, never a clip.
- **The foot glow** (`CardGlow`, Core/Runtime): the app's color rises from the card's foot to 40% of its height
  (stops 1, .55 at 15%, .18 at 28%, 0 at 40%), at 11% (light) or 16% (dark) on a solid ground and 8% or 12% on glass,
  0.6 of that on a selected card. The sampled color is normalized in OKLCH: its hue kept, lightness 0.70 (light) and
  0.66 (dark), chroma at most 0.12. A hue within 22° of basil or 18° of gold is muted (chroma 0.05, 70% strength), so
  color never reads as focus or a collection; a near-neutral icon (Terminal) glows not at all. No glow on a picture,
  a color or a covered card, nor under Increase Contrast. `CardGlowTests` checks text over the strongest glow of every
  hue in both appearances: 7:1 for the content and 4.5:1 for the foot line. The panel proposed lightness 0.74 in dark,
  which failed that check.
- **On iOS** the foot line leads with the app's icon (16 pt) when the catalog has it.

## Consequences
- The glow is deliberately faint; whether it reads on a device and on the Mac's glass is a hand check, and the Mac's
  cards follow in their own change.
- The keyboard, the AutoFill picker and the widgets do not show the icon or the glow yet: their sealed sets would have
  to carry them. Recorded in the backlog.
- A Mac with many apps rewrites a file of up to about 1 MB when its list changes; the newest 128 apps are kept.

## Docs affected
- `docs/design/ios-library.md`, `docs/sync-design.md`
- `Sources/Core/Sync/CLAUDE.md` (the new file in a device's folder)
- `decisions/README.md`
