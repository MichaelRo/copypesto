#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Keeps what `make bench-shelf` measured, run after run, and says when a number has drifted.

    perf_history.py record <summary.json>... [--note text]    append one line to docs/perf/history/shelf.jsonl
    perf_history.py trend [--last 8]                          the latest runs per metric, newest last, and any drift

A line holds the date, the commit, the machine (a number from a faster Mac says nothing about a slower one) and the main
figure of each drive of the `imported` seed. Drift is a metric more than 25% (and 3 ms or 0.5 of a count) worse than the
median of the previous five runs on the same machine. The file is committed: its diff is the history.
"""
import datetime
import json
import os
import platform
import re
import statistics
import subprocess
import sys

HISTORY = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "perf", "history", "shelf.jsonl")
# (key, drive, kind, name, field): the figures a run keeps.
METRICS = [
    ("arrowStep.p95", "benchArrowSteps", "interval", "focusMove", "p95"),
    ("arrowStep.cards", "benchArrowSteps", "render", "focusMove/ClipboardCard", "mean"),
    ("arrowHold.p95", "benchArrowHold", "interval", "focusMove", "p95"),
    ("switch.p50", "benchCycleCollections", "interval", "collectionSwitch", "p50"),
    ("switch.p95", "benchCycleCollections", "interval", "collectionSwitch", "p95"),
    ("switchHold.keyP95", "benchCycleHold", "interval", "collectionKey", "p95"),
]
RELATIVE, ABSOLUTE = 0.25, 3.0


def sh(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def machine():
    return f"{sh('sysctl', '-n', 'machdep.cpu.brand_string') or platform.machine()} / macOS {platform.mac_ver()[0]}"


def metric(summary, kind, name, field):
    if kind == "interval":
        row = summary.get("intervals", {}).get(name)
        return None if row is None else row[field]
    interaction, view = name.split("/")
    row = summary.get("renders", {}).get(interaction, {}).get(view)
    return 0.0 if row is None else row[field]


def entry(paths, note="", now=None):
    values = {}
    for path in paths:
        found = re.search(r"-imported-(?P<drive>bench[A-Za-z]+)\.json$", os.path.basename(path))
        if not found:
            continue
        with open(path) as handle:
            summary = json.load(handle)
        for key, drive, kind, name, field in METRICS:
            if drive == found.group("drive"):
                measured = metric(summary, kind, name, field)
                if measured is not None:
                    values[key] = measured
    return {
        "date": (now or datetime.datetime.now(datetime.timezone.utc)).strftime("%Y-%m-%dT%H:%MZ"),
        "commit": sh("git", "rev-parse", "--short", "HEAD"),
        "branch": sh("git", "rev-parse", "--abbrev-ref", "HEAD"),
        "dirty": bool(sh("git", "status", "--porcelain", "-uno")),
        "machine": machine(),
        "note": note,
        "values": values,
    }


def drift(entries, latest):
    """Metrics of `latest` that are worse than the median of the previous five runs on the same machine."""
    same = [e for e in entries if e["machine"] == latest["machine"] and e is not latest][-5:]
    problems = []
    for key, now in latest["values"].items():
        before = [e["values"][key] for e in same if key in e["values"]]
        if len(before) < 3:
            continue
        base = statistics.median(before)
        if now > base * (1 + RELATIVE) and now - base >= (0.5 if key.endswith("cards") else ABSOLUTE):
            problems.append(f"{key}: {now} against a median of {base} over the last {len(before)} runs")
    return problems


def load(path=HISTORY):
    if not os.path.exists(path):
        return []
    with open(path) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def trend(entries, last=8):
    lines = []
    for key, *_ in METRICS:
        series = [(e["date"][:10], e["values"][key]) for e in entries if key in e["values"]][-last:]
        if series:
            lines.append(f"{key:<20} " + "  ".join(f"{value:g}" for _, value in series) + f"   ({series[0][0]} .. {series[-1][0]})")
    return lines


def main(argv):
    if not argv:
        sys.exit(__doc__)
    if argv[0] == "record":
        note = argv[argv.index("--note") + 1] if "--note" in argv else ""
        paths = [a for a in argv[1:] if a.endswith(".json")]
        new = entry(paths, note)
        if not new["values"]:
            sys.exit("perf_history: no imported-seed summaries to record")
        os.makedirs(os.path.dirname(HISTORY), exist_ok=True)
        entries = load()
        problems = drift(entries + [new], new)
        with open(HISTORY, "a") as handle:
            handle.write(json.dumps(new, sort_keys=True) + "\n")
        print("history: recorded", ", ".join(f"{k}={v:g}" for k, v in new["values"].items()))
        for problem in problems:
            print("history: DRIFT", problem)
        return 0
    if argv[0] == "trend":
        last = int(argv[argv.index("--last") + 1]) if "--last" in argv else 8
        entries = load()
        print("\n".join(trend(entries, last)) or "history: nothing recorded yet")
        if entries:
            for problem in drift(entries, entries[-1]):
                print("history: DRIFT", problem)
        return 0
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
