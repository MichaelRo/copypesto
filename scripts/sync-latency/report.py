#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Joins Mac A's writer.log with Mac B's reader.log and prints the latency from "the writer finished the file" to
"B first saw it" (by FSEvents, by the poll and by whichever came first) and to "B could read it" (the probe), as
p50 and p95 per size, plus how many files arrived dataless. Writes the table to --out when given.

  report.py --writer writer.log --reader reader.log --out docs/perf/sync-latency-2026-11.md --label "awake, Wi-Fi"
"""
import argparse
import json
import math
import sys
from collections import defaultdict


def percentile(values, fraction):
    if not values:
        return float("nan")
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, math.ceil(fraction * len(ordered)) - 1))
    return ordered[index]


def read_lines(path):
    with open(path) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--writer", required=True)
    parser.add_argument("--reader", required=True)
    parser.add_argument("--out")
    parser.add_argument("--label", default="")
    args = parser.parse_args()

    written = {row["file"]: row for row in read_lines(args.writer)}
    first = defaultdict(dict)
    probes = {}
    for row in read_lines(args.reader):
        name = row["file"]
        if row["event"] == "seen":
            first[name].setdefault(row["via"], row["at"])
        elif row["event"] == "probe":
            probes[name] = row

    series = defaultdict(lambda: defaultdict(list))
    dataless = defaultdict(int)
    missed = defaultdict(int)
    for name, row in written.items():
        kind = row["kind"]
        seen = first.get(name)
        if not seen:
            missed[kind] += 1
            continue
        start = row["written"]
        series[kind]["first seen (either)"].append(min(seen.values()) - start)
        if "fsevent" in seen:
            series[kind]["FSEvents"].append(seen["fsevent"] - start)
        if "poll" in seen:
            series[kind]["poll"].append(seen["poll"] - start)
        probe = probes.get(name)
        if probe:
            series[kind]["readable"].append(probe["at"] - start)
            if probe.get("dataless"):
                dataless[kind] += 1

    lines = [f"| Size | Measure | Files | p50 s | p95 s | max s |", "|---|---|---|---|---|---|"]
    for kind in ("small", "large"):
        for measure in ("first seen (either)", "FSEvents", "poll", "readable"):
            values = series[kind][measure]
            if not values:
                continue
            lines.append(f"| {kind} | {measure} | {len(values)} | {percentile(values, 0.5):.1f} | "
                         f"{percentile(values, 0.95):.1f} | {max(values):.1f} |")
    notes = [f"- {kind}: {dataless[kind]} of {len(series[kind]['readable'])} arrived as dataless placeholders, "
             f"{missed[kind]} never seen" for kind in ("small", "large")]
    text = (f"### {args.label}\n\n" if args.label else "") + "\n".join(lines) + "\n\n" + "\n".join(notes) + "\n"
    print(text)
    if args.out:
        with open(args.out, "a") as handle:
            handle.write("\n" + text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
