#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Parse Pesto benchmark logs, evaluate thresholds, and emit JSON + Markdown summaries."""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any

EXTRACTORS: list[tuple[re.Pattern[str], list[tuple[str, int]]]] = [
    (
        re.compile(r"PERF sync ingest per clip:\s*off\s+([\d.]+)\s+ms,\s+on\s+([\d.]+)\s+ms"),
        [("sync_copy_off_ms", 1), ("sync_copy_on_ms", 2)],
    ),
    (
        re.compile(r"PERF sync\b.*\bidle pass\s+([\d.]+)\s+ms"),
        [("sync_idle_pass_ms", 1)],
    ),
    (
        re.compile(r"PERF similarity index build\s+([\d.]+)\s+ms"),
        [("similarity_index_build_ms", 1)],
    ),
    (
        re.compile(r"PERF similarity lookup\s+([\d.]+)\s+us average"),
        [("similarity_lookup_us", 1)],
    ),
    (
        re.compile(r"PERF widget-snapshot 24 collections:\s*([\d.]+)\s+ms"),
        [("widget_snapshot_24_collections_ms", 1)],
    ),
    (
        re.compile(r"PERF widget-snapshot 1 collection:\s*([\d.]+)\s+ms"),
        [("widget_snapshot_1_collection_ms", 1)],
    ),
    (
        re.compile(r"PERF search keystroke over 5,000 clips:\s*slowest\s+([\d.]+)\s+ms"),
        [("search_keystroke_5000_ms", 1)],
    ),
    (
        re.compile(
            r"PERF collection switch over 5,000 clips:.*cold\s+([\d.]+)\s+ms,\s+warm\s+([\d.]+)\s+ms"
        ),
        [("collection_switch_cold_ms", 1), ("collection_switch_warm_ms", 2)],
    ),
    (
        re.compile(r"PERF watcher idle at 0\.2\s*seconds:\s*([\d.]+)%"),
        [("watcher_idle_200ms_cpu_pct", 1)],
    ),
    (
        re.compile(r"PERF watcher idle at 0\.06\s*seconds:\s*([\d.]+)%"),
        [("watcher_idle_60ms_cpu_pct", 1)],
    ),
    (
        re.compile(r"PERF paste-write text\b.*median\s+([\d.]+)\s+ms"),
        [("paste_write_text_ms", 1)],
    ),
    (
        re.compile(r"PERF paste-write image\b.*median\s+([\d.]+)\s+ms"),
        [("paste_write_image_ms", 1)],
    ),
    (
        re.compile(r"PERF history fetch of 5000 items:\s*\+?(-?[\d.]+)\s+MB"),
        [("history_fetch_5000_mb", 1)],
    ),
    (
        re.compile(r"^memory:\s*([\d.]+)\s+MB footprint on the large history, shelf open", re.MULTILINE),
        [("memory_steady_open_mb", 1)],
    ),
    (
        re.compile(r"^idle-cpu:\s*([\d.]+)% over 30s with SyncFolderWatcher active", re.MULTILINE),
        [("idle_cpu_sync_pct", 1)],
    ),
]


def parse_logs(texts: list[str]) -> dict[str, float]:
    """Extract numeric benchmark metrics from raw log strings."""
    metrics: dict[str, float] = {}
    for text in texts:
        for pattern, targets in EXTRACTORS:
            for match in pattern.finditer(text):
                for key, group_idx in targets:
                    metrics[key] = float(match.group(group_idx))
    return metrics


def evaluate(
    measured: dict[str, float], thresholds: dict[str, Any], mode: str
) -> tuple[list[dict[str, Any]], bool]:
    """Compare measured values against mode ('local' or 'ci') thresholds."""
    budget_field = "ci_max" if mode == "ci" else "local_max"
    rows: list[dict[str, Any]] = []
    passed = True
    any_measured = False

    for key, spec in thresholds.get("metrics", {}).items():
        budget = float(spec[budget_field])
        unit = spec["unit"]
        label = spec["label"]
        optional = mode == "ci" and bool(spec.get("optional_in_ci", False))
        value = measured.get(key)

        if value is None:
            status = "SKIP" if optional else "MISSING"
            if not optional:
                passed = False
        else:
            any_measured = True
            if value <= budget:
                status = "PASS"
            else:
                status = "FAIL"
                passed = False

        rows.append(
            {
                "key": key,
                "label": label,
                "value": value,
                "budget": budget,
                "unit": unit,
                "status": status,
            }
        )

    if not any_measured:
        passed = False
    return rows, passed


def render_markdown(rows: list[dict[str, Any]], mode: str, passed: bool) -> str:
    """Format benchmark results as a GitHub-flavored Markdown summary."""
    overall = "PASS" if passed else "FAIL"
    lines = [
        f"## Pesto Benchmarks ({mode} mode): {overall}",
        "",
        "| Metric | Measured | Budget | Status |",
        "|---|---:|---:|---|",
    ]
    for row in rows:
        measured_str = "—" if row["value"] is None else f"{row['value']:.2f} {row['unit']}"
        budget_str = f"<= {row['budget']:.2f} {row['unit']}"
        lines.append(f"| {row['label']} | {measured_str} | {budget_str} | {row['status']} |")
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Evaluate Pesto benchmark logs against thresholds.")
    parser.add_argument("logs", nargs="+", help="Log files to parse.")
    parser.add_argument("--thresholds", default="scripts/bench-thresholds.json", help="Thresholds JSON path.")
    parser.add_argument("--mode", choices=("local", "ci"), default="local", help="Budget profile.")
    parser.add_argument("--json-out", help="Write structured JSON report to this path.")
    parser.add_argument("--summary-out", help="Append Markdown summary to this path (e.g. $GITHUB_STEP_SUMMARY).")
    args = parser.parse_args(argv)

    thresholds = json.loads(pathlib.Path(args.thresholds).read_text(encoding="utf-8"))
    texts = [pathlib.Path(p).read_text(encoding="utf-8", errors="replace") for p in args.logs]
    measured = parse_logs(texts)
    rows, passed = evaluate(measured, thresholds, args.mode)
    markdown = render_markdown(rows, args.mode, passed)

    print(markdown)

    if args.json_out:
        out_path = pathlib.Path(args.json_out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"mode": args.mode, "passed": passed, "metrics": rows}
        out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    if args.summary_out:
        summary_path = pathlib.Path(args.summary_out)
        summary_path.parent.mkdir(parents=True, exist_ok=True)
        with summary_path.open("a", encoding="utf-8") as handle:
            handle.write(markdown + "\n")

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
