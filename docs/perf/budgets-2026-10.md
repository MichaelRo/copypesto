# Performance budgets: baselines and what enforces them (2026-10-04)

The budgets are in `AGENTS.md`. Each row says what measures it, the baseline on a developer Mac (an M-series MacBook
Pro, macOS 27), and where it fails. Assertions run on a developer Mac only (`RunEnvironment.isCI`); CI shared runners
are about twice as slow, so there the tests only measure.

| Budget | Enforced by | Baseline | Fails when |
|---|---|---|---|
| Overlay open to first paint under 100 ms | `OverlayPerformanceTests` (the window's show, flush and hide); `make bench-latency open` (the real show, after a copy made while it was closed) | 43 ms synchronous; 61 to 64 ms to commit after a copy (2026-10-22, three runs, medians; it was 124 to 165 ms while every show started a retention sweep, P-01, and 222 ms before the history was followed while hidden; the first show of a run is still 330 ms, over the budget on its own; 32 ms on 2026-10-10 and 46 ms with the sweep deleted in the review's experiment) | the show path takes 100 ms or more |
| Memory steady-state under 150 MB | `scripts/check-memory-budget.sh [budget] [open or closed]` (a step of `scripts/verify.sh`), on a Profile build over the 5,000-clip history, 20 s after opening | **69–70 MB** shelf open (2026-10-22, with `MallocLargeCache=0` applied by the script, P-02; 88–99 MB before it did), 52 MB closed (history held from launch), peak 172 MB while opening | the footprint is 150 MB or more |
| Memory over 300 large pictures scrolled to the end under 150 MB (P-06) | `scripts/check-memory-budget.sh 150 pictures` (a step of `scripts/verify.sh`; the `pictures` seed, then the `walkShelfToEnd` command draws every card once) | **125 MB** (2026-10-23, two runs of the same figure on the 70 MB text baseline) after the thumbnail cache's byte limit went from 96 to 48 MB (`ThumbnailCacheTests`); 175 MB before | the footprint is 150 MB or more |
| Shelf open under 100 ms, after a copy made while it was closed (P-01) | `ShelfOpenLatencyTests` (a step of the gate, Debug build, 5 opens over 5,000 clips); `make bench-latency open` (Profile build, real hotkey path; by hand) | Debug median 92 ms, first open of a launch 368 ms (2026-10-23); the bench measured 124 ms before the sweep left the open path (P-01) | the Debug median is 150 ms or more; the bench is 100 ms or more |
| Memory after long copies under 150 MB | `make bench-latency memory` (200 x 1 MB texts and 50 screenshots, shelf open); `LongCopyMemoryTests` (opt in with `TEST_RUNNER_PESTO_LONG_COPY_MEMORY=1`, 2 minutes) | **79 to 80 MB** after, peak 176 MB (2026-10-22, `MallocLargeCache=0` applied by the script; 131 to 134 MB without it, 215 MB before the large-block cache was turned off through `LSEnvironment` in `Info.plist`) | the footprint after is 150 MB or more |
| Memory of the history in a fetch | `HistoryMemoryTests` | a 5,000-item fetch adds 18 MB (2026-10-22, now printed as a `PERF` line) | it adds 40 MB or more |
| Watcher CPU under 0.5% idle | `WatcherPerformanceTests` (process CPU over four 3 s windows, the quietest counts; watcher at its fixed 200 ms on an idle pasteboard) | 0.42% in the full suite, 0.25% alone | the quietest window is 0.5% or more |
| Ingest, text-like clips, over a 5,000-clip store | `CopyLatencyPerformanceTests` (also `IngestPipelinePerformanceTests`, empty store, 50 ms) | 2 to 3 ms | 50 ms or more |
| Ingest, picture, GIF, 5 MB text (when the clip is on the shelf) | `CopyLatencyPerformanceTests` | picture 205 to 225 ms, GIF 9 ms, 5 MB text 61 ms (728, 424 and 433 ms before ADR 0006) | a picture 400 ms, a GIF 100 ms or a large text 200 ms or more |
| Search keystroke over 5,000 clips under 4 ms | `LargeHistoryPerformanceTests` (the history index with the lookup of the clips that pass) | 1.3 ms in the Debug test host, 0.2 ms optimised (79 ms before ADR 0007) | 4 ms or more |
| Writing a clip to the pasteboard | `PasteWritePerformanceTests` | 0.1 to 1.5 ms every kind | 5 ms, or 20 ms for a picture or a large text |
| Hover card build | `HoverCardPerformanceTests` | 4 to 11 ms, +2.8 MB over 50 opens | 30 ms, or +40 MB |
| Paste, key press to clip in the target app | `make bench-latency paste` (fails over budget; a dropped paste is a row with no arrival) | text 151 ms, other kinds 173 to 188 ms, 5 MB text 634 ms of which 450 ms is the target's own layout (776, 790 and 1,228 ms before ADR 0009) | 300 ms for a kind, 900 ms for the large clip, or any paste that never arrives |
| Copy to card on the shelf | `make bench-latency copy` | text 54 ms, link 86 ms, picture 108 ms, GIF 45 ms, 5 MB text 185 ms (308, 301, 820, 749 and 782 ms before ADRs 0007, 0006) | 200 ms for a kind, 400 ms for the large clip |
| Hover card, pointer rest to visible | `make bench-latency hover` | 306 to 320 ms, of which 400 ms of dwell is by design and counted from before the pointer rests | 600 ms |
| 60 fps scroll over 5,000 clips | `make bench-scroll` (needs an unlocked Mac, real scroll events and Accessibility for the terminal, so it is not part of the gate); `scripts/profile-scroll/check-budget.py` fails a run far worse than the baseline | large (5,000 text): 25 to 33 hitches, 375 to 492 ms; mixed (1,200 with pictures): 29 to 39 hitches, 475 to 808 ms; pictures (300 large pictures only, `make bench-scroll`, 2026-10-23): 39 hitches, 575 to 592 ms with the 48 MB thumbnail cache and with the old 96 MB one; median frame 16.1 ms (2026-10-22, four runs, a helper that really scrolls: 5,700 points of travel; the 2026-10-02 code measures the same, so this is not a regression). The 2026-10-01 figures (3 / 25 and 6 / 50) were taken when the helper's events did not move the shelf (`docs/reviews/performance.md`, P-06) | a run shows more than twice the baseline hitches or hitch time, with a floor of 20 hitches or 200 ms, or the shelf travels under 300 points |
| Undo and redo over a 5,000-clip store | `make bench-undo` (`UndoPerformanceTests`, `UndoHistoryMemoryTests`); numbers in `undo-2026-10.md` | to be recorded on a Mac | recording a 200-clip delete adds 100 ms, a restore takes 100 ms, one edit adds 5 ms, a 200-clip reorder takes 100 ms, the stack outgrows its 16 MB |
| Sync cost (copy, first send and receive, idle pass) | `SyncPerformanceTests` (`PESTO_SYNC_PERF_CLIPS`); numbers in `sync-2026-10.md` | copy 2.55 ms off and 3.5 ms on; idle pass 1.5 ms every 30 s | a copy 50 ms or more, an idle pass 100 ms or more |
| Backup write | `BackupWritePerformanceTests` (`PESTO_BACKUP_CLIPS` for the large case) | 2,000 clips 0.26 s, 20,000 clips 2.8 s (7,100 clips a second); memory grows 4 KB a clip, SQLite's page cache while the store is read (a context per page changed nothing) | memory over 20 MB plus 6 KB a clip |
| Restore of a large backup | `BackupRestorePerformanceTests` (`PESTO_RESTORE_CLIPS=20000` for the large case) | 20,000 clips in 65 s; 2,000 in 5 s | never asserted: measured, see ADR 0010 |

## What the memory measurement found

Opening the shelf over 5,000 clips took the app from 41 MB to a peak of 410 MB and left it at 220 MB for as long as it
ran, 141 MB of which was freed buffers the allocator kept (`vmmap` showed "Malloc Large (empty)" regions of 4, 4, 8, 16,
32 and 64 MB, twice: a buffer that doubles as it grows).

The cause was resolving a source app's icon. `SourceAppResolver` made the thumbnail and the dominant colour from
`NSImage.tiffRepresentation`, which encodes every size an app icon holds: 64 MB per icon, done twice, the first time the
shelf showed each app, inside a SwiftUI `body`. A history from a handful of apps was enough. `SourceIconMemoryTests`
resolved five icons and grew resident memory by 1.9 GB (Debug build); the icon is now drawn once at 96 pixels, and the
same five icons cost under 24 MB. Opening the shelf now peaks at 172 MB and settles at 70 MB.

`malloc_zone_pressure_relief` does not return those freed blocks on macOS 27, and `MallocLargeCache=0` does but is an
undocumented setting, so the fix is not to build the buffers.

## What the 2026-10-10 review changed

The end-to-end numbers and the stage splits are in `review-2026-10-10.md`. Footprint after long copies was dominated by
libmalloc keeping the large buffers of picture decodes (+110 MB); `MallocLargeCache=0` in `LSEnvironment` returns them at
once (the earlier note that this was "undocumented, so the fix is not to build the buffers" stands as the first choice, but the
buffers come from ImageIO and Vision, which Pesto does not control). Check once by hand that a LaunchServices launch carries
it: `ps eww <pid> | tr ' ' '\n' | grep Malloc`.

