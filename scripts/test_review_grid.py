#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Unit tests for scripts/review_grid.py."""
from __future__ import annotations

import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import review_grid


class ReviewGridTests(unittest.TestCase):
    def test_routes_single_lens(self) -> None:
        grid = review_grid.build_grid(["Sources/Core/Sync/SyncEngine.swift"])
        ids = [cell["id"] for cell in grid]
        self.assertEqual(ids, ["core-concurrency", "security-crypto", "perf-budgets"])

    def test_routes_tooling_and_encryption_test(self) -> None:
        grid = review_grid.build_grid(
            ["Makefile", ".github/workflows/benchmarks.yml", "Tests/PestoCoreTests/OnDiskEncryptionTests.swift"]
        )
        ids = [cell["id"] for cell in grid]
        self.assertEqual(ids, ["core-concurrency", "security-crypto", "tooling-ci-docs"])

    def test_empty_diff_produces_empty_grid(self) -> None:
        self.assertEqual(review_grid.build_grid([]), [])
        self.assertIn("No changed files detected", review_grid.render_markdown([], []))

    def test_static_checks_catch_code_violations_and_ignore_comments(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            bad = root / "Sources/Core/Bad.swift"
            bad.parent.mkdir(parents=True, exist_ok=True)
            bad.write_text("import SwiftUI\nimport Sentry\nlet d = UserDefaults.standard\n", encoding="utf-8")

            doc_only = root / "Sources/Core/Runtime/DocOnly.swift"
            doc_only.parent.mkdir(parents=True, exist_ok=True)
            doc_only.write_text("/// Mentions `NSPasteboard.general` and `UserDefaults.standard`.\n", encoding="utf-8")

            violations = review_grid.run_static_checks(
                ["Sources/Core/Bad.swift", "Sources/Core/Runtime/DocOnly.swift"], root
            )
            self.assertEqual(len(violations), 3)

    def test_json_output_includes_prompts(self) -> None:
        grid = review_grid.build_grid(["Sources/Mobile/LibraryView.swift"])
        payload = json.loads(json.dumps({"lenses": grid}))
        self.assertEqual(payload["lenses"][0]["id"], "ios-extensions")
        self.assertIn("Sources/Mobile/LibraryView.swift", payload["lenses"][0]["prompt"])


if __name__ == "__main__":
    unittest.main()
