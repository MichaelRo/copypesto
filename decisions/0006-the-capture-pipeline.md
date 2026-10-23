# 0006. The watcher polls on an input-driven timer, a copy shows at once and is judged afterwards, and ingest is bounded

Status: Accepted

## Context
`NSPasteboard` posts no notification when it changes, only `changeCount`, so a clipboard manager polls. A copy nearly
always follows input (⌘C or a click), which predicts when the board is about to change. Judging a copy (OCR, the model's
screening of a picture, link checks, the secret scan) is slow, but nothing sensitive may become visible before it is
judged.
Ingest cost does not follow one quantity: text follows bytes (about 115 ms and 10 MB of memory per megabyte), a picture
follows pixels (a decoded bitmap is 4 bytes a pixel, OCR about 10, and a flat PNG is a few megabytes at any size).

## Decision
**Polling.** `PasteboardWatcher` uses a `DispatchSourceTimer` on its own serial queue, not a runloop `Timer`, which
stops
firing while a modal panel changes the runloop mode and would drop copies made under a file dialog. With
`start(adaptive: true)` the period is `PollPolicy.period(secondsSinceInput:)`: 60 ms for 3 seconds after the last key,
click or pointer movement, 200 ms up to 30 seconds, 500 ms after that. Input age comes from
`CGEventSource.secondsSinceLastEventType`, which needs no permission. A tick that finds another running returns; the
next
tick takes the copy in order. The idle CPU budget (`AGENTS.md`) is for the 500 ms tier, and `start()` without `adaptive`
keeps the fixed 200 ms period that the budget test measures. There are no tiers by battery or thermal state.

**A picture, or a text over 100 KB (`StorageService.backgroundTextBytes`), is saved first and judged afterwards.**
`StorageService.ingest` classifies it, checks for a duplicate, applies the ingest rules, encrypts it and saves it with
`ClipboardItem.analysisPending = true`; `startAnalysis` then reads its text, asks the model, checks the link and scans
for
secrets, and `finishAnalysis` fills in the preview or OCR text, sensitivity and content-filter mark and clears the flag.
At
most two clips are judged at a time (`analysisSlots`). Shorter text, links, colors and files are judged before saving.
- Nothing readable is stored while a clip is pending: no preview, OCR text or mask. The card shows an opaque "Checking"
  surface, `CardConcealment` covers it through `pendingAnalysis` (no hover card, Quick Look, AI action or drag) and it
does
  not decode its picture. A paste works at once (ADR 0003).
- A pending clip is invisible to what would describe it: the last-item file (ADR 0011) is written when it is judged, a
  backup leaves it out and counts it withheld, and it has no search text or vector.
- A clip pending at quit is judged at the next launch (`resumePendingAnalysis`); one deleted meanwhile stays deleted.
  `waitForBackgroundWork()` waits for judging and search vectors.
- Nothing suspends between the final duplicate check and the insert, so two copies arriving together find each other.

**Bounds.**
- Bytes (`ClipSizePolicy`): text-like copies (`public.text`, `public.url`) up to 10 MB (`maxTextBytes`), pictures and
  other
  data up to 100 MB (`maxOtherBytes`). Text appended to the latest clip may not exceed the limit. Nothing is truncated;
a
  refusal (`ClipSizePolicy.TooLarge`) shows a plain banner on the shelf for two minutes.
- Pixels: nothing decodes above `ImageDownsampler.maxDecodedPixels` (24 MP, a full 6K screen) at full size.
  `ImageDownsampler.boundedImage` scales larger pictures down; OCR (`OCRService`) and any new reader of picture pixels
use
  it or `ImageDownsampler.thumbnailPNG`. `PerceptualHasher.pixelDigest` uses the same limit; a picture over it is never
a
  duplicate.
- Decodes: the 8x8 perceptual hash only nominates candidates (Hamming distance at most `similarityThreshold` 5, among
  the
  newest 50 pictures, `StorageService+Dedup`); a duplicate needs identical decoded pixels, and at most
  `PerceptualHasher.maxDecodedCandidates` (5) nominees are compared, so one copy costs at most five decodes.
- OCR: `.accurate` with language correction on a detached utility task, on device, only after the duplicate check,
  stored
  as the preview capped at 500 characters and scanned for secrets like any text. A failed read is logged, not "no text".
  Pictures over 24 MP are read from the scaled copy; tiling would find more at several times the cost and is not done.
- Secret scan: `SensitiveContentDetector.maxScannedBytes` equals `maxTextBytes`, so no accepted text has an unscanned
  tail.
  One pass sees at most `maxWindowBytes` (50,000); larger text goes in windows of whole lines, a longer line in
  10,000-character pieces. A pattern spanning a window boundary can be missed.

## Consequences
- Copy to card is within the `AGENTS.md` budgets (`make bench-latency copy`); a picture's verdict arrives about half a
  second later and uncovers the card. Wait from copy to notice is about 30 ms after input instead of 100 ms.
- `NSPasteboard.setData` does not bump `changeCount`, so a writer that clears the board and then waits can hide its clip
  from a poll between the two; Pesto builds the data first.
- A reader of every clip's preview must expect an empty one; a test that reads a picture's verdict calls
  `waitForBackgroundWork()`. The limits are constants: raising one needs new measurements.
- Tests: `PollPolicyTests`, `WatcherPerformanceTests`, `CardFirstIngestTests`, `IngestConcurrencyTests`,
  `CopyLatencyPerformanceTests`, `ClipSizePolicyTests`, `ClipSizeLimitTests`, `ImageDownsamplerTests`,
  `LargePictureMemoryTests`, `OCRLargePictureAccuracyTests`, `SensitiveContentDetectorTests`.

## Docs affected
- `Sources/Core/Pasteboard/CLAUDE.md`
- `Sources/Core/Storage/CLAUDE.md`
- `docs/perf/budgets-2026-10.md`
- `docs/testing.md`
