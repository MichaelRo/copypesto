#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""How smoothly the shelf scrolled, from the gaps between its scroll updates (no profiler needed).

    scroll_cadence.py <perf-timeline.tsv>

While the shelf scrolls, SwiftUI reports a new offset once per frame it produces, and the app writes a `scrollFrame` event for
each. A gap well above the display's frame time is a frame that was late: the main thread was busy. A gap over a second is the
pause between sweeps, not a hitch. Prints the number of frames, the gaps' p50 / p95 / max and the share over 16.7 and 33 ms.
"""
import re
import statistics
import sys


def gaps(path):
    times = []
    with open(path) as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 4 and re.match(r"scrollFrame\(", parts[1]):
                times.append(int(parts[2]) / 1e6)
    times.sort()
    return [b - a for a, b in zip(times, times[1:]) if b - a < 200], len(times)


def summarise(values, frames):
    if not values:
        return {"frames": frames, "p50": 0, "p95": 0, "max": 0, "over17": 0, "over33": 0}
    ordered = sorted(values)
    return {
        "frames": frames,
        "p50": round(statistics.median(ordered), 1),
        "p95": round(ordered[min(len(ordered) - 1, int(0.95 * len(ordered)))], 1),
        "max": round(ordered[-1], 1),
        "over17": round(100 * sum(v > 16.7 for v in ordered) / len(ordered), 1),
        "over33": round(100 * sum(v > 33.3 for v in ordered) / len(ordered), 1),
    }


if __name__ == "__main__":
    values, frames = gaps(sys.argv[1])
    row = summarise(values, frames)
    print(f"frames {row['frames']}  gap p50 {row['p50']} p95 {row['p95']} max {row['max']} ms  over 16.7 ms {row['over17']}%  over 33 ms {row['over33']}%")
