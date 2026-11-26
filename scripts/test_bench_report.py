#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Unit tests for scripts/bench_report.py."""
from __future__ import annotations

import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import bench_report


THRESHOLDS = json.loads(
    (pathlib.Path(__file__).resolve().parent / "bench-thresholds.json").read_text(encoding="utf-8")
)

SAMPLE_LOG = """\
PERF sync ingest per clip: off 2.15 ms, on 3.10 ms (2000 clips)
PERF sync 2000 clips: send 0.12 s (cpu 0.10 s, +1.2 MB), receive 0.15 s (cpu 0.11 s, +1.5 MB), idle pass 1.45 ms (every 30 s: 0.0048 % of one core)
PERF similarity index build 420.5 ms for 5000 signatures
PERF similarity lookup 180.2 us average over 400 queries
PERF widget-snapshot 24 collections: 68.7 ms
PERF widget-snapshot 1 collection: 9.2 ms
PERF search keystroke over 5,000 clips: slowest 1.32 ms of [0.8, 1.32]
PERF collection switch over 5,000 clips: collection of 1,000 cold 2.10 ms, warm 0.45 ms; all 0.60 ms
PERF watcher idle at 0.2 seconds: 0.24% of a core (7.2 ms in 3.0 s, quietest window)
PERF watcher idle at 0.06 seconds: 0.31% of a core (9.3 ms in 3.0 s, quietest window)
PERF paste-write text (12 bytes): median 0.42 ms (min 0.30, max 0.90)
PERF paste-write image (4096 bytes): median 14.50 ms (min 12.10, max 20.00)
PERF history fetch of 5000 items: +18.2 MB resident
memory: 69.5 MB footprint on the large history, shelf open (budget 150 MB)
idle-cpu: 0.180% over 30s with SyncFolderWatcher active (budget < 0.5%)
"""


class BenchReportTests(unittest.TestCase):
    def test_parses_all_metrics_and_passes_local(self) -> None:
        measured = bench_report.parse_logs([SAMPLE_LOG])
        rows, passed = bench_report.evaluate(measured, THRESHOLDS, "local")
        self.assertTrue(passed, rows)
        self.assertTrue(all(r["status"] == "PASS" for r in rows))

    def test_detects_regression_over_budget(self) -> None:
        regressed = SAMPLE_LOG.replace("slowest 1.32 ms", "slowest 15.00 ms")
        measured = bench_report.parse_logs([regressed])
        rows, passed = bench_report.evaluate(measured, THRESHOLDS, "ci")
        self.assertFalse(passed)
        by_key = {r["key"]: r for r in rows}
        self.assertEqual(by_key["search_keystroke_5000_ms"]["status"], "FAIL")

    def test_ci_mode_allows_optional_profile_metrics_to_skip(self) -> None:
        without_profile = "\n".join(
            line
            for line in SAMPLE_LOG.splitlines()
            if not line.startswith(("memory:", "idle-cpu:", "PERF history fetch"))
        )
        measured = bench_report.parse_logs([without_profile])
        rows_ci, passed_ci = bench_report.evaluate(measured, THRESHOLDS, "ci")
        self.assertTrue(passed_ci, rows_ci)
        by_key = {r["key"]: r for r in rows_ci}
        self.assertEqual(by_key["memory_steady_open_mb"]["status"], "SKIP")

        _, passed_local = bench_report.evaluate(measured, THRESHOLDS, "local")
        self.assertFalse(passed_local)

    def test_empty_log_fails(self) -> None:
        measured = bench_report.parse_logs([""])
        _, passed = bench_report.evaluate(measured, THRESHOLDS, "ci")
        self.assertFalse(passed)

    def test_cli_writes_json_and_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = pathlib.Path(tmp)
            log_file = tmp_path / "bench.log"
            json_file = tmp_path / "report.json"
            summary_file = tmp_path / "summary.md"
            log_file.write_text(SAMPLE_LOG, encoding="utf-8")

            rc = bench_report.main(
                [
                    str(log_file),
                    "--mode",
                    "local",
                    "--thresholds",
                    str(pathlib.Path(__file__).resolve().parent / "bench-thresholds.json"),
                    "--json-out",
                    str(json_file),
                    "--summary-out",
                    str(summary_file),
                ]
            )
            self.assertEqual(rc, 0)
            data = json.loads(json_file.read_text(encoding="utf-8"))
            self.assertTrue(data["passed"])
            self.assertIn("Pesto Benchmarks (local mode): PASS", summary_file.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
