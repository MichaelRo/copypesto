# 0077. A sealed fingerprint rules out lookalike pictures without decoding them

Status: Accepted

Amends ADR 0006's decode bound. The rest of it stands.

## Context
- The 8×8 hash nominates up to 5 lookalikes, and each nominee, and the new picture, paid a full decode
  (`pixelDigest`, 85 to 92 ms at 5120×2880, debug). Screenshots of one window are lookalikes of each other, so a copy
  took 244 to 617 ms against the 200 ms budget for copy to card.
- ImageIO does not scale the same pixels the same way from every file. Measured on one 5K picture at 8 to 512 px:
  a PNG against the same pixels as TIFF, BMP, interlaced PNG or 16-bit PNG differs by up to 57 levels of 255, more
  than a changed word does (digit changed: at most 5 at 256 px, 26 at 512 px, nothing at 64 px). A tolerance that lets
  identical pixels through would let different screenshots through too.
- The same file layout is scaled deterministically: other density, text chunks or compression filter gave identical
  results, and so did TIFF uncompressed, LZW and PackBits.
- Deriving the 8×8 hash from a larger thumbnail moves it by up to 26 bits, which would strand the stored hashes.
  ImageIO keeps no decoded picture between two thumbnails, so one pass cannot serve both unchanged.

## Decision
- `PictureFingerprint` is two SHA-256 digests. `reading` covers what decides how ImageIO scales the file: the system
  version, container, pixel size, bit depth, bitmap layout, color model and profile, orientation and PNG interlacing.
  `pixels` covers the picture scaled to at most 512 px.
- It only rules a nominee **out**: same `reading`, different `pixels`. Anything else is compared by `pixelDigest`, as
  before. It never makes two pictures a duplicate.
- Only a PNG of at most `ImageDownsampler.maxDecodedPixels` gets one. A lossy file also matches a copy that is
  merely close (`isCrossFormatNearMatch`), which a digest cannot judge. TIFF is left out: the same pixels stored
  tiled or planar scale differently from stripped ones, and ImageIO does not report the planar layout. Screenshots are
  PNG, which the watcher takes ahead of TIFF.
- It is taken at ingest, so the next copy always finds it, in a thumbnail pass of its own that runs side by side
  with the 8×8 hash's (`PictureFingerprint.withCoarseHash`). An interlaced PNG runs the two in turn. The full decode
  of the new picture happens only if a nominee is left.
- Rejected: computing it after the save or only when a nominee asks (a second write to the clip and new orderings
  between copies, to save what running side by side already saves), and one decode for both passes (the 8×8 hash
  derived from anything larger moves further than its threshold).
- It is **sealed metadata** (`ItemMetadata.pictureFingerprint`, ADR 0002), not a column: a digest of the picture
  confirms a guess about it, nothing queries it, and metadata needs no schema stage. It is never synced or backed up:
  it depends on this device's decoder, and sync apply and restore go through `ingest`, which takes it again. Undo
  carries it with the rest of the metadata. Replacing a picture's bytes (the GIF upgrade) drops it.
- No migration. A clip without one is compared by its pixels.

## Consequences
- Measured (debug, `CopyLatencyPerformanceTests`, 5,000-clip store, 5K, three runs): a lookalike new card takes 40 to
  52 ms (262 to 620 ms with the ruling-out switched off), an unlike one 42 to 53 ms (38 to 45 ms before this change).
  With the two passes in turn, two runs gave 73 to 85 ms for both.
- Side by side, the passes use a second core. On a busy Mac a copy takes up to the in-turn time.
- Peak memory, standalone optimized probe at 6000×4000, side by side against in turn: 21 against 13 MB (flat), 95
  against 88 MB (noise), 181 against 168 MB (16-bit noise), 265 against 172 MB (interlaced, hence in turn).
- Still over 200 ms at 5K, each paying full decodes as before:
  - a copy of pixels already in the history in another file (209 to 216 ms: the new picture and the one match);
  - lookalikes saved before this change or before a system update, until 5 newer lookalikes replace them;
  - a lookalike read differently (interlaced, another bit depth or profile), a change too small to show at 512 px,
    and TIFF and lossy pictures.
- A system update that does not change the version string but changes ImageIO's scaling could store an identical
  picture twice, which costs a card (ADR 0006). So would a PNG layout that scales differently and is not in `reading`.
  Removing Apple's `iDOT` chunk changed nothing on the one large system PNG tried; a fresh macOS screenshot with it
  was not measured.
- Tests: `LookalikeDedupeTests`, `PictureFingerprintTests`, `PerceptualDedupeTests`, `GIFUpgradeTests`,
  `CopyLatencyPerformanceTests`.

## Docs affected
- `AGENTS.md`
- `Sources/Core/Pasteboard/CLAUDE.md`
- `Sources/Core/Storage/CLAUDE.md`
- `decisions/README.md`
- `docs/perf/budgets-2026-10.md`
