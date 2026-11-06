# 0032. A Paste import keeps the pinboards and the newest history that fits, and says so before it starts

Status: Accepted

Supersedes the Paste bounds of ADR 0011 (a library over 20,000 records or 1 GB is `tooLarge` and refused whole). Everything else in 0011 stands: the copy is read-only, every clip goes through `PasteMigrator` and `StorageService.ingest`, and the other ten importers keep their bounds.

## Context
A person with a big Paste library got "That file is too large to import" and nothing: not their pinboards, which are the clips they curated, and not the recent history. Three more things turned up reading the code:
- Pesto's own retention removes unpinned clips older than *Keep clips for* (30 days) or past *Keep at most* (5,000, at most 10,000) at launch and every six hours. History imported past that is encrypted, indexed and deleted hours later, and the sweep can delete clips the person already had to make room.
- The reader held every payload, base64-encoded, for as long as the preview sheet was open. A library of any size cost its full size in memory.
- A text over 10 MB (`ClipSizePolicy`) made `ingest` throw, which ended the whole import.

## Decision
- **What is taken.** Pinboards first, in Paste's board and in-board order, pinned as before. Then history, newest first (date, then the later row). The first clip that does not fit ends the list, so "the newest N" is exactly that.
- **The cap** is 20,000 clips and 1,000,000,000 bytes of payload (`ImportCap.paste`), both inclusive. The 1 GB counts the bytes imported, not the size of the file, so a larger file is read.
- **Retention.** The selected history is run, with the clips already in Pesto, through `RetentionPruner.computeEvictions` under the person's settings. History it would remove again is not imported. Clips already in Pesto it would remove to make room are counted and named in the sheet. Pinboard clips are pinned and exempt.
- **Pinboards over the cap** are cut in board order, and the sheet says "the first N from your collections". History is then not taken.
- **A clip with no payload or over 50 MB** (`maxRecordBytes`) takes no slot and does not end the list; it is counted as left out. A clip in several lists counts once; a pinboard beats history, and the first board wins.
- **History stays opt-in** when there are pinboards (ADR 0011).
- **No silent loss.** Before importing the sheet reads one sentence, "X of Y clips will be imported: your collections and the newest N.", where Y is the whole library and X what the plan takes with the history choice as set, with a caption for each reason clips stay behind. It appears only when a limit leaves clips out. After the import, a summary that stays on screen until the next import or leaving the pane: "N clips imported. M stayed in Paste because of the limits. K were left out (duplicates, excluded apps, unreadable, too large)." Imported + left out + stayed + clips with no payload is Y; a test holds that.
- **Streaming.** `PasteLibrarySnapshot` keeps a read-only copy of the library and reads it in two ways. `plan` reads each clip's size (`length()` of the payload, which does not load it) and date, and keeps only the clips it selects (about 50 bytes each). `records(for:)` then reads 64 clips or 32 MB at a time, decoding each in its own autorelease pool: without it Foundation objects from unarchiving piled up for the whole import (441 MB over a 400 MB library, 21 MB with it). Between groups the migrator waits for the background judging and search vectors `ingest` leaves for later, so that backlog is one group too. Progress is "Importing… 4,200 of 20,000".
- **One huge text no longer ends an import.** `PasteMigrator` counts a clip over the size Pesto keeps as left out and goes on; this applies to every importer.
- **The copy** lives in a temporary folder while the sheet is open and is removed on Cancel, when the import ends, or when the snapshot is released. A folder a crashed Pesto left is removed on the next open if it is a day old. Free space is checked before the copy (`notEnoughSpace`).

## Consequences
- On default settings a Paste import brings in clips from the last 30 days, at most 5,000: the sentence says so and names *Keep clips for* and *Keep at most* as the way to bring in more. The "N of them are older than … and will go" caption no longer applies to Paste, because those clips are not imported.
- The file can be larger than the cap; the temporary copy needs that space (an APFS volume clones it).
- Measured on a development Mac, Debug build, in-memory store: 2,000 short clips import in about 5.7 s (2.8 ms each); reading a 400 MB library in groups raised the process footprint by 21 MB. A 20,000-clip import on a real store, and a single 50 MB clip (its decoded copies are held at once), were not measured.
- Tests: `PasteImportPlanTests` (cap edges, order, pinboards, retention, the sum), `PasteLibraryReaderTests` (ordering, 20,001 rows, a file over 1 GB, no leftovers), `PasteImportStreamingTests` (end to end, twice, memory), `PasteMigratorTests` (a text over the limit), `ImportPreviewTests`, `ImportReportTests`, `ImportPreviewUITests` (compiled, not run).

## Docs affected
`docs/guide/moving-from.md`, `decisions/0011-read-only-surfaces.md` (status line), `decisions/README.md`.
