#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Reads a shelf bench's perf-timeline.tsv and prints, per interaction, how long the shelf took to commit it and how
much work it caused.

    shelf_report.py <perf-timeline.tsv> [--json out.json]

Lines are `channel<TAB>name<TAB>start_ns<TAB>end_ns`. Intervals (`focusMove`, `collectionSwitch`, `collectionFilter`,
`collectionApply`, `linkFetch`, `metadataSave`, `historyApply`) are summarised as count / p50 / p95 / max in ms; `renders(...)`
events carry body counts and are summarised per interaction as the mean and max count per step.
"""
import json
import re
import sys
from collections import defaultdict

INTERVALS = ["focusMove", "collectionSwitch", "collectionFilter", "collectionApply", "linkFetch", "metadataSave",
             "historyApply", "historyRefresh", "retentionSweep"]


def percentile(values, q):
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(round(q * (len(ordered) - 1))))
    return ordered[index]


def parse(path):
    intervals = defaultdict(list)
    renders = defaultdict(lambda: defaultdict(list))
    scroll_offsets = []
    with open(path) as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 4:
                continue
            _, name, start, end = parts
            duration_ms = (int(end) - int(start)) / 1e6
            match = re.match(r"renders\((\S+) (.*)\)$", name)
            if match:
                for pair in match.group(2).split():
                    key, _, value = pair.partition("=")
                    renders[match.group(1)][key].append(int(value))
                continue
            offset = re.match(r"shelfScroll\((-?\d+)\)", name)
            if offset:
                scroll_offsets.append(int(offset.group(1)))
                continue
            if name in INTERVALS:
                intervals[name].append(duration_ms)
    return intervals, renders, scroll_offsets


def summarise(intervals, renders, scroll_offsets):
    result = {"intervals": {}, "renders": {}, "scrollTravel": (max(scroll_offsets) - min(scroll_offsets)) if scroll_offsets else 0}
    for name, values in intervals.items():
        result["intervals"][name] = {
            "count": len(values), "p50": round(percentile(values, 0.5), 2),
            "p95": round(percentile(values, 0.95), 2), "max": round(max(values), 2),
        }
    for interaction, counts in renders.items():
        result["renders"][interaction] = {
            view: {"mean": round(sum(v) / len(v), 1), "max": max(v), "steps": len(v)} for view, v in counts.items()
        }
    return result


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    summary = summarise(*parse(sys.argv[1]))
    print(f"{'interval':<18}{'count':>6}{'p50 ms':>9}{'p95 ms':>9}{'max ms':>9}")
    for name in INTERVALS:
        row = summary["intervals"].get(name)
        if row:
            print(f"{name:<18}{row['count']:>6}{row['p50']:>9}{row['p95']:>9}{row['max']:>9}")
    for interaction, views in summary["renders"].items():
        cells = "  ".join(f"{view}: mean {c['mean']} max {c['max']}" for view, c in sorted(views.items()))
        print(f"body runs per {interaction}: {cells}")
    if "--json" in sys.argv:
        with open(sys.argv[sys.argv.index("--json") + 1], "w") as out:
            json.dump(summary, out, indent=2)


if __name__ == "__main__":
    main()
