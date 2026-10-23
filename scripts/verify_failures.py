#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""One line per failing test from an xcresult summary, or the arguments that re-run just those tests.

    verify_failures.py <tests-summary.json>                 one line per failure: target/Suite/test: message
    verify_failures.py <tests-summary.json> --only-testing  -only-testing:... arguments for xcodebuild

A failure with no test of its own (the UI-test runner timing out before any test started) re-runs its whole target.
"""
import json
import sys

MESSAGE_LIMIT = 240


def identifier(failure):
    """target/Suite/test for a failure that names a test, else None."""
    name = failure.get("testIdentifierString", "")
    if "/" not in name:
        return None
    return "%s/%s" % (failure.get("targetName", "?"), name.removesuffix("()"))


def one_line(text):
    text = " ".join((text or "").split("\n")[0].split())
    return text if len(text) <= MESSAGE_LIMIT else text[:MESSAGE_LIMIT] + "…"


def main():
    summary = json.load(open(sys.argv[1]))
    failures = summary.get("testFailures") or []
    if "--only-testing" in sys.argv[2:]:
        whole_targets = {f.get("targetName", "?") for f in failures if identifier(f) is None}
        tests = {identifier(f) for f in failures if identifier(f) and f.get("targetName", "?") not in whole_targets}
        for argument in sorted(whole_targets) + sorted(tests):
            print("-only-testing:%s" % argument)
        return
    for failure in failures:
        label = identifier(failure) or "%s: %s" % (failure.get("targetName", "?"), failure.get("testIdentifierString", "?"))
        print("%s: %s" % (label, one_line(failure.get("failureText"))))


if __name__ == "__main__":
    main()
