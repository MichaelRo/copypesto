#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Fails when a scroll benchmark shows far more hitches than the recorded baseline (docs/perf/budgets-2026-10.md).

Reads the output of scripts/profile-scroll.sh on stdin. A single run varies a lot (docs/perf/scroll-2026-10.md), so the
limit is a multiple of the baseline with a floor: only a large gap means something.

    check-budget.py <mixed|large|pictures>
"""
import re
import sys

# seed: (baseline hitches, baseline hitch time in ms). Measured on 2026-10-22 with a scroll helper that really moves the
# shelf (5,700 points of travel): mixed 29 to 39 hitches and 475 to 808 ms, large 25 to 33 hitches and 375 to 492 ms,
# on the code of 2026-10-02 as well as today's, so nothing regressed. pictures (300 large pictures only): 39 hitches and
# 575 to 592 ms with the 48 MB thumbnail cache and with the old 96 MB one (2026-10-23), so the smaller cache costs nothing. The earlier baselines (6 / 50 and 3 / 25) came from
# a helper whose events the shelf ignored (P-06), so they measured a shelf that was not scrolling.
BASELINE = {"mixed": (35, 600), "large": (30, 430), "pictures": (39, 580)}
FACTOR = 2
FLOOR_HITCHES = 20
FLOOR_MS = 200


def limits(seed):
    hitches, ms = BASELINE[seed]
    return max(hitches * FACTOR, FLOOR_HITCHES), max(ms * FACTOR, FLOOR_MS)


def parse(text):
    match = re.search(r"pesto hitches: (\d+) total ms (\d+)", text)
    if not match:
        raise SystemExit("check-budget: no 'pesto hitches' line in the benchmark output")
    return int(match.group(1)), int(match.group(2))


def main():
    seed = sys.argv[1]
    if seed not in BASELINE:
        raise SystemExit(f"check-budget: no baseline for '{seed}'")
    hitches, ms = parse(sys.stdin.read())
    max_hitches, max_ms = limits(seed)
    print(f"scroll budget ({seed}): {hitches} hitches / {ms} ms against {max_hitches} / {max_ms}")
    if hitches > max_hitches or ms > max_ms:
        raise SystemExit("check-budget: the shelf scrolls much worse than its baseline")


if __name__ == "__main__":
    main()
