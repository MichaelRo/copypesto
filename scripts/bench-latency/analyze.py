#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Joins the bench driver's rows with Pesto's perf timeline (both on CLOCK_UPTIME_RAW, in nanoseconds) and prints, per
kind of clip, the median (and min and max) of each stage in milliseconds.

    analyze.py paste|copy <work-dir>
"""
import statistics
import sys
from collections import defaultdict

MS = 1_000_000


def load_rows(path):
    rows = []
    for line in open(path):
        kind, run, t0, t1 = line.rstrip("\n").split("\t")
        rows.append((kind, int(run), int(t0), int(t1)))
    return rows


def load_timeline(path):
    records = []
    for line in open(path):
        channel, name, start, end = line.rstrip("\n").split("\t")
        records.append((channel, name, int(start), int(end)))
    return sorted(records, key=lambda r: r[2])


def first(records, channel, name, after, before, prefix=False):
    for channel_, name_, start, end in records:
        if start < after or start > before or channel_ != channel:
            continue
        if name_ == name or (prefix and name_.startswith(name)):
            return start, end
    return None


# Budgets in milliseconds, judged on the median of the runs (docs/perf/budgets-2026-10.md).
BUDGETS = {
    "paste": ("key to arrival", {"large": 900}, 300),
    "copy": ("copy to card", {"large": 400}, 200),
    "open": ("show call to commit", {}, 100),
    "hover": ("pointer rest to visible", {}, 600),
}


def violations(mode, table):
    column, per_kind, default = BUDGETS[mode]
    found = []
    for kind, samples in table.items():
        values = [s[column] for s in samples if s.get(column) is not None]
        limit = per_kind.get(kind, default)
        if not values:
            found.append(f"{kind}: no {column} measured (a paste that never arrived, or a copy that never showed)")
        elif statistics.median(values) > limit:
            found.append(f"{kind}: median {column} {statistics.median(values):.0f} ms is over its budget of {limit} ms")
    return found


def summarize(title, columns, table):
    print(f"\n{title}")
    header = f"{'kind':<10}" + "".join(f"{c:>26}" for c in columns)
    print(header)
    for kind, samples in table.items():
        cells = []
        for column in columns:
            values = [s[column] for s in samples if s.get(column) is not None]
            if not values:
                cells.append(f"{'-':>26}")
            else:
                cells.append(f"{statistics.median(values):>9.1f} ({min(values):.0f}-{max(values):.0f}){'':>4}"[:26].rjust(26))
        print(f"{kind:<10}" + "".join(cells))


def horizons(rows):
    """Each row's window ends where the next row begins, so one run never picks up another run's stages."""
    starts = sorted(r[2] for r in rows)
    result = {}
    for _kind, _run, t0, _t1 in rows:
        later = [s for s in starts if s > t0]
        result[t0] = min(later) - 1 if later else t0 + 8_000 * MS
    return result


def paste(rows, timeline):
    table = defaultdict(list)
    ends = horizons(rows)
    columns = ["key to arrival", "key to paste start", "writeItem", "activate", "axWrite or cmdV", "paste end to arrival"]
    for kind, _run, t0, t1 in rows:
        horizon = ends[t0]
        coordinator = first(timeline, "Paste", "coordinatorPaste", t0, horizon)
        write = first(timeline, "Paste", "writeItem", t0, horizon)
        activate = first(timeline, "Paste", "activate", t0, horizon)
        inject = first(timeline, "Paste", "axWrite", t0, horizon) or first(timeline, "Paste", "commandV", t0, horizon)
        sample = {
            "key to arrival": (t1 - t0) / MS if t1 else None,
            "key to paste start": (coordinator[0] - t0) / MS if coordinator else None,
            "writeItem": (write[1] - write[0]) / MS if write else None,
            "activate": (activate[1] - activate[0]) / MS if activate else None,
            "axWrite or cmdV": (inject[1] - inject[0]) / MS if inject else None,
            "paste end to arrival": (t1 - coordinator[1]) / MS if coordinator and t1 else None,
        }
        table[kind].append(sample)
    summarize("Paste, ms: median (min-max). Arrival is the moment the target app's text view changed.", columns, table)
    missed = [(k, r) for k, r, _t0, t1 in rows if not t1]
    if missed:
        print(f"\nNo arrival within 3 s: {missed}")
    return violations("paste", table) + ([f"{len(missed)} pastes never arrived"] if missed else [])


def copy(rows, timeline):
    table = defaultdict(list)
    ends = horizons(rows)
    columns = ["poll wait", "ingest", "copy to history", "copy to card", "copy to judged", "copy to preview"]
    for kind, _run, written, _ in rows:
        horizon = ends[written]
        tick = first(timeline, "Copy", "watcherTick", written, horizon)
        ingest = first(timeline, "Copy", "ingest", written, horizon)
        card = first(timeline, "Shelf", "cardAppear", ingest[1] if ingest else written, horizon, prefix=True)
        judged = first(timeline, "Copy", "analysis", ingest[0] if ingest else written, horizon)
        previews = [r for r in timeline if r[0] == "Shelf" and r[1].startswith("cardThumbnail")
                    and (card[0] if card else written) <= r[2] <= horizon]
        table[kind].append({
            "poll wait": (tick[0] - written) / MS if tick else None,
            "ingest": (ingest[1] - ingest[0]) / MS if ingest else None,
            "copy to history": (ingest[1] - written) / MS if ingest else None,
            "copy to card": (card[0] - written) / MS if card else None,
            "copy to judged": (judged[1] - written) / MS if judged else None,
            "copy to preview": (previews[-1][2] - written) / MS if previews else None,
        })
    summarize("Copy, ms: median (min-max). History is the end of ingest's save; card is the card's first task.", columns, table)

    stages = ["dedup", "classify", "perceptualHash", "rules", "analysis", "resolveSourceApp",
              "recheckDuplicate", "encrypt", "save"]
    inside = defaultdict(list)
    for kind, _run, written, _ in rows:
        ingest = first(timeline, "Copy", "ingest", written, ends[written])
        if not ingest:
            continue
        sample = {}
        for channel, name, start, end in timeline:
            if channel == "Copy" and name in stages and ingest[0] <= start <= ingest[1]:
                sample[name] = (end - start) / MS
        inside[kind].append(sample)
    summarize("Inside ingest, ms: median (min-max)", stages, inside)
    return violations("copy", table)


def opened(rows, timeline):
    table = defaultdict(list)
    ends = horizons(rows)
    columns = ["show call to commit", "refresh at show", "to first card task", "to last preview"]
    for kind, _run, t0, _ in rows:
        show = first(timeline, "Shelf", "overlayShow", t0, ends[t0])
        if not show:
            continue
        cards = [r for r in timeline if r[0] == "Shelf" and r[1].startswith("cardAppear") and show[0] <= r[2] <= ends[t0]]
        previews = [r for r in timeline if r[0] == "Shelf" and r[1].startswith("cardThumbnail") and show[0] <= r[2] <= ends[t0]]
        refresh = first(timeline, "Shelf", "historyRefresh", t0, ends[t0])
        table[kind].append({
            "show call to commit": (show[1] - show[0]) / MS,
            "refresh at show": (refresh[1] - refresh[0]) / MS if refresh else 0.0,
            "to first card task": (cards[0][2] - show[0]) / MS if cards else None,
            "to last preview": (previews[-1][2] - show[0]) / MS if previews else None,
        })
    summarize("Opening the shelf, ms: median (min-max). The command queue's own polling delay is excluded.", columns, table)
    return violations("open", table)


def hover(rows, timeline):
    table = defaultdict(list)
    ends = horizons(rows)
    columns = ["pointer rest to visible", "present to visible"]
    for kind, _run, rested, _ in rows:
        present = first(timeline, "Shelf", "hoverCardPresent", rested - 300 * MS, ends[rested])
        table[kind].append({
            "pointer rest to visible": (present[1] - rested) / MS if present else None,
            "present to visible": (present[1] - present[0]) / MS if present else None,
        })
    summarize("Hover card, ms: median (min-max). Pointer rest includes the 400 ms dwell.", columns, table)
    return violations("hover", table)


if __name__ == "__main__":
    mode, work = sys.argv[1], sys.argv[2]
    rows = load_rows(f"{work}/bench-{mode}.tsv")
    timeline = load_timeline(f"{work}/perf-timeline.tsv")
    problems = {"paste": paste, "copy": copy, "open": opened, "hover": hover}[mode](rows, timeline)
    if problems:
        print("\nOVER BUDGET:\n  " + "\n  ".join(problems))
        sys.exit(1)
