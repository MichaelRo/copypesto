#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Lists where the main thread spent its time in a Time Profiler trace export.

    xcrun xctrace export --input run.trace --xpath '/trace-toc/run/data/table[@schema="time-profile"]' > tp.xml
    top_frames.py tp.xml [--top 25] [--match Pesto]

Prints the frames present in the most main-thread samples (inclusive), then the ones that were the innermost frame
(self), as a share of all main-thread samples. `--leaf NAME` lists the callers (eight frames up) of samples whose innermost frame contains NAME. `--under NAME` keeps only samples that have a frame named NAME and counts the frames called below it (where
a view's body spends its time). `--match` keeps only frames whose name or library contains the text in the
inclusive list, which is how to see Pesto's own and SwiftUI's frames without the run loop above them.
"""
import sys
import xml.etree.ElementTree as ET
from collections import Counter


def frame_name(frame, names):
    if frame.get("ref") is not None:
        return names.get(frame.get("ref"), "?")
    name = frame.get("name") or "?"
    binary = frame.find("binary")
    if binary is not None and binary.get("name"):
        name = f"{name}  [{binary.get('name')}]"
    if frame.get("id") is not None:
        names[frame.get("id")] = name
    return name


def analyse(path, match=None, under=None, leaf=None, leaf_callers=None):
    """xctrace writes each thread, frame and backtrace once and refers to it by id afterwards, so all three are kept."""
    names, threads, stacks = {}, {}, {}
    inclusive, own = Counter(), Counter()
    total = 0
    for _, element in ET.iterparse(path, events=("end",)):
        if element.tag != "row":
            continue
        thread = element.find("thread")
        if thread is not None and thread.get("id") is not None:
            threads[thread.get("id")] = thread.get("fmt") or ""
        label = threads.get(thread.get("ref")) if thread is not None and thread.get("ref") else (
            thread.get("fmt") if thread is not None else "")
        backtrace = element.find("tagged-backtrace")
        if backtrace is None:
            element.clear()
            continue
        if backtrace.get("ref") is not None:
            frames = stacks.get(backtrace.get("ref"), [])
        else:
            frames = [frame_name(frame, names) for frame in backtrace.iter("frame")]
            if backtrace.get("id") is not None:
                stacks[backtrace.get("id")] = frames
        if "Main Thread" not in (label or "") or not frames:
            element.clear()
            continue
        if under is not None:
            hit = next((i for i, name in enumerate(frames) if under in name), None)
            if hit is None:
                element.clear()
                continue
            frames = frames[:hit]
            if not frames:
                element.clear()
                continue
        total += 1
        own[frames[0]] += 1
        if leaf is not None and leaf in frames[0] and leaf_callers is not None:
            leaf_callers[tuple(name[:70] for name in frames[1:9])] += 1
        for name in set(frames):
            if match is None or match in name:
                inclusive[name] += 1
        element.clear()
    return total, inclusive, own


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    top = int(sys.argv[sys.argv.index("--top") + 1]) if "--top" in sys.argv else 25
    match = sys.argv[sys.argv.index("--match") + 1] if "--match" in sys.argv else None
    under = sys.argv[sys.argv.index("--under") + 1] if "--under" in sys.argv else None
    leaf = sys.argv[sys.argv.index("--leaf") + 1] if "--leaf" in sys.argv else None
    leaf_callers = Counter()
    total, inclusive, own = analyse(sys.argv[1], match, under, leaf, leaf_callers)
    if leaf is not None:
        print(f"-- callers of {leaf} (innermost first)")
        for stack, count in leaf_callers.most_common(top):
            print(f"{count:4d}  " + "  <-  ".join(stack))
        return
    print(f"main-thread samples: {total}")
    print("-- inclusive")
    for name, count in inclusive.most_common(top):
        print(f"{100 * count / max(total, 1):5.1f}%  {name[:140]}")
    print("-- self")
    for name, count in own.most_common(top):
        print(f"{100 * count / max(total, 1):5.1f}%  {name[:140]}")


if __name__ == "__main__":
    main()
