# iCloud Drive latency (phase 0 of ADR 0018)

Measures how long a file written on Mac A takes to be seen on Mac B through iCloud Drive, so the poll interval and the
budget in `docs/sync-design.md` come from numbers. Nothing here ships and nothing here touches Pesto's data: the files
go into a folder of their own, and the logs stay on each Mac.

Both Macs: same Apple Account, iCloud Drive on, awake, on Wi-Fi, Pesto does not need to run. Do this once per condition
below. About 65 minutes each.

## Set up (once per Mac)
```bash
swiftc -swift-version 5 -O scripts/sync-latency/reader.swift -o /tmp/sync-latency-reader
```

The shared folder is `~/Library/Mobile Documents/com~apple~CloudDocs/Pesto Latency` on both Macs. Call it `FOLDER`.

## One run (same `RUN` name on both Macs, started within a minute of each other)
On each Mac, first the clock offset against Apple's time (`sntp` reads it and does not change the clock):
```bash
OFFSET=$(scripts/sync-latency/clock-offset.sh)
```

Mac B (reads), start it first:
```bash
/tmp/sync-latency-reader --folder "$FOLDER" --offset "$OFFSET" --log reader.log --duration 3900
```

Mac A (writes a 4 KB and a 5 MB file every 30 s for an hour):
```bash
python3 scripts/sync-latency/writer.py --folder "$FOLDER" --offset "$OFFSET" --log writer.log --duration 3600 --run RUN
```

Copy `reader.log` to Mac A (AirDrop is fine), then on Mac A:
```bash
python3 scripts/sync-latency/report.py --writer writer.log --reader reader.log --label "awake, Wi-Fi" --out docs/perf/sync-latency-2026-11.md
```

## Conditions to repeat (change the label)
1. Both awake on Wi-Fi.
2. Mac B put to sleep for 10 minutes in the middle, then woken (the reader keeps its log).
3. Mac B in Low Power Mode.
4. Mac B with *Optimize Mac Storage* on (System Settings → Apple Account → iCloud → iCloud Drive), so files arrive as
   dataless placeholders. Run it twice: once as is (`pread` waits for the download) and once with
   `--hydrate download` on the reader (`startDownloadingUbiquitousItem` first).

## What to read
- *FSEvents* is how soon Mac B is told; *poll* is the 5 s fallback; *first seen* is whichever came first; *readable*
  includes the wait for a dataless file to download.
- The report counts files that arrived dataless and files never seen in the hour.
- The three questions from `docs/sync-design.md`: does FSEvents fire on a download into `com~apple~CloudDocs` (FSEvents
  rows have files), does `startDownloadingUbiquitousItem` work outside an app container (the second dataless run
  finishes), and what `pread` does on a dataless file (`readMs` in `reader.log`).

Delete the `Pesto Latency` folder from iCloud Drive when you are done.
