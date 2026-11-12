#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Fails when `make bench-shelf` shows the shelf doing more than its budget on the imported-shaped history.

    check-shelf-budget.py <summary.json>...        # files `shelf_report.py --json` wrote, named <label>-<seed>-<drive>.json

Two kinds of limit. Render counts (view bodies run per step) are deterministic, so they are tight: a focus move that re-runs
the overlay or every card is the regression this exists to catch. Times are a multiple of what a developer Mac measures
(docs/perf/shelf-2026-11.md), because a single run varies by several milliseconds; only a large gap means something. Only the
`imported` seed is judged (the history the limits were set on); the others are printed. Under CI (shared runners, about twice
as slow) nothing fails.
"""
import json
import os
import re
import sys

# drive: [(kind, name, field, limit)] where kind is "interval" (name = signpost) or "render" (name = "<interaction>/<view>").
BUDGETS = {
    "benchArrowSteps": [
        ("interval", "focusMove", "p95", 35),
        ("render", "focusMove/ClipboardCard", "mean", 5),
        ("render", "focusMove/GridView", "mean", 1.5),
        ("render", "focusMove/OverlayRootView", "mean", 0.1),
    ],
    "benchArrowHold": [
        ("interval", "focusMove", "p95", 35),
        ("render", "focusMove/ClipboardCard", "mean", 6),
        ("render", "focusMove/OverlayRootView", "mean", 0.1),
    ],
    "benchCycleCollections": [
        ("interval", "collectionSwitch", "p50", 80),
        ("interval", "collectionSwitch", "p95", 100),
        ("render", "collectionSwitch/OverlayRootView", "mean", 1.5),
    ],
    "benchCycleHold": [
        ("interval", "collectionKey", "p95", 50),
    ],
}
JUDGED_SEED = "imported"


def value(summary, kind, name, field):
    if kind == "interval":
        row = summary.get("intervals", {}).get(name)
        return None if row is None else row[field]
    interaction, view = name.split("/")
    row = summary.get("renders", {}).get(interaction, {}).get(view)
    return 0.0 if row is None else row[field]  # a view that never ran is a count of zero


def check(drive, summary):
    """Returns (rows, failures): rows are (name, field, measured, limit) for the report."""
    rows, failures = [], []
    for kind, name, field, limit in BUDGETS.get(drive, []):
        measured = value(summary, kind, name, field)
        if measured is None:
            failures.append(f"{drive}: {name} was not recorded")
            continue
        rows.append((name, field, measured, limit))
        if measured > limit:
            failures.append(f"{drive}: {name} {field} {measured} is over {limit}")
    return rows, failures


def main(paths):
    failures = []
    under_ci = os.environ.get("CI") == "true"
    for path in paths:
        match = re.search(r"-(?P<seed>[a-z]+)-(?P<drive>bench[A-Za-z]+)\.json$", os.path.basename(path))
        if not match:
            continue
        seed, drive = match.group("seed"), match.group("drive")
        with open(path) as handle:
            rows, problems = check(drive, json.load(handle))
        judged = seed == JUDGED_SEED
        for name, field, measured, limit in rows:
            flag = "" if measured <= limit else "  OVER" if judged else "  (over; not judged)"
            print(f"budget {seed}/{drive}: {name} {field} {measured} (limit {limit}){flag}")
        if judged:
            failures += problems
    if failures and under_ci:
        print("budget: over budget on a CI runner, which is not judged:\n  " + "\n  ".join(failures))
        return 0
    if failures:
        print("budget: FAILED\n  " + "\n  ".join(failures))
        return 1
    print("budget: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
