#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Judges the test output of a verify run: counts, floors and skips.

  verify_judge.py core  CORE_LOG
  verify_judge.py hosted TESTS_JSON [--no-ui] [--snapshots]   (TESTS_JSON: `xcresulttool get test-results tests --compact`)

Prints a one-line summary, then one line per problem. Exits 1 when a floor is missed or a test was skipped that
scripts/verify-allowed-skips.txt does not name, so a green summary cannot hide tests that did not run.
"""
import json
import pathlib
import re
import sys

CORE_SWIFT_TESTING_FLOOR = 950
CORE_XCTEST_FLOOR = 30
HOSTED_FLOOR = 270
UI_FLOOR = 130
SNAPSHOT_FLOOR = 30

ALLOWED_SKIPS_FILE = pathlib.Path(__file__).with_name("verify-allowed-skips.txt")


def allowed_skips(path=ALLOWED_SKIPS_FILE):
    lines = path.read_text().splitlines() if path.exists() else []
    return [line.strip() for line in lines if line.strip() and not line.startswith("#")]


def is_allowed(name, allowed):
    return any(pattern in name for pattern in allowed)


def judge_core(log, allowed=None):
    allowed = allowed_skips() if allowed is None else allowed
    text = re.sub(r"\x1b\[[0-9;]*m", "", log)
    runs = [int(n) for n in re.findall(r"Test run with (\d+) tests?", text)]
    executed = [int(n) for n in re.findall(r"Executed (\d+) tests?", text)]
    swift_testing = max(runs, default=0)
    xctest = executed[-1] if executed else 0
    skipped = re.findall(r'Test "(.*?)" skipped', text)
    problems = []
    if swift_testing < CORE_SWIFT_TESTING_FLOOR:
        problems.append(f"only {swift_testing} Swift Testing tests ran, expected at least {CORE_SWIFT_TESTING_FLOOR}")
    if xctest < CORE_XCTEST_FLOOR:
        problems.append(f"only {xctest} XCTest tests ran, expected at least {CORE_XCTEST_FLOOR}")
    problems += [f"unexpected skip: {name}" for name in skipped if not is_allowed(name, allowed)]
    summary = f"{swift_testing} Swift Testing + {xctest} XCTest, {len(skipped)} skipped"
    if len(runs) > 1:
        summary += f" (runs: {'+'.join(map(str, runs))})"
    return summary, problems


def collect_cases(tree):
    cases = []

    def walk(node, bundle):
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            bundle = node.get("name")
        if node.get("nodeType") == "Test Case":
            cases.append((bundle, node.get("nodeIdentifier", node.get("name", "?")), node.get("result")))
        for child in node.get("children", []):
            walk(child, bundle)

    for node in tree.get("testNodes", []):
        walk(node, None)
    return cases


def judge_hosted(tree, includes_ui=True, includes_snapshots=False, allowed=None):
    allowed = allowed_skips() if allowed is None else allowed
    cases = collect_cases(tree)
    passed = {"PestoTests": 0, "PestoUITests": 0, "PestoSnapshotTests": 0}
    skipped = []
    for bundle, identifier, result in cases:
        if result == "Passed" and bundle in passed:
            passed[bundle] += 1
        elif result == "Skipped":
            skipped.append(identifier)
    problems = []
    if passed["PestoTests"] < HOSTED_FLOOR:
        problems.append(f"only {passed['PestoTests']} hosted tests passed, expected at least {HOSTED_FLOOR}")
    if includes_ui and passed["PestoUITests"] < UI_FLOOR:
        problems.append(f"only {passed['PestoUITests']} UI tests passed, expected at least {UI_FLOOR}")
    if includes_snapshots and passed["PestoSnapshotTests"] < SNAPSHOT_FLOOR:
        problems.append(
            f"only {passed['PestoSnapshotTests']} snapshot tests passed, expected at least {SNAPSHOT_FLOOR}"
        )
    problems += [f"unexpected skip: {name}" for name in skipped if not is_allowed(name, allowed)]
    summary = f"hosted={passed['PestoTests']} ui={passed['PestoUITests']} skipped={len(skipped)}"
    if includes_snapshots:
        summary += f" snapshots={passed['PestoSnapshotTests']}"
    return summary, problems


def main(argv):
    if len(argv) < 3 or argv[1] not in ("core", "hosted"):
        print(__doc__)
        return 2
    if argv[1] == "core":
        summary, problems = judge_core(pathlib.Path(argv[2]).read_text(errors="replace"))
    else:
        tree = json.loads(pathlib.Path(argv[2]).read_text())
        summary, problems = judge_hosted(
            tree, includes_ui="--no-ui" not in argv, includes_snapshots="--snapshots" in argv
        )
    print(summary)
    for problem in problems:
        print(f"PROBLEM: {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
