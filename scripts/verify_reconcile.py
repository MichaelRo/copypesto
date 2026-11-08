#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Reconciles a passing verify-rerun-failed.sh run against its parent verify.sh run.

    verify_reconcile.py --repo <dir> --run-dir <dir> --stamp <stamp>

Writes .build/verify-receipt.json (and refs/notes/verify when full_gate is true) only when:
1. The current working tree is clean and HEAD^{tree} matches the original run's tree.
2. Every non-test step in the original run passed.
3. The rerun summary has 0 failures.
4. Merging the rerun test tree over the original test tree clears every original failure and passes verify_judge.judge_hosted.
"""
import argparse
import copy
from datetime import datetime, timezone
import json
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import verify_judge  # noqa: E402

TEST_STEP_NAMES = {"hosted + UI tests", "hosted tests (UI skipped)", "snapshots"}


def normalize_id(raw):
    return (raw or "").removesuffix("()")


def merge_test_trees(orig_tree, rerun_tree, orig_failures):
    merged = copy.deepcopy(orig_tree)
    rerun_cases_by_bundle = {}
    rerun_bundles = {}

    def walk_rerun(node, bundle):
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            bundle = node.get("name")
            rerun_bundles[bundle] = node
        if node.get("nodeType") == "Test Case" and bundle:
            ident = normalize_id(node.get("nodeIdentifier") or node.get("name"))
            rerun_cases_by_bundle.setdefault(bundle, {})[ident] = node
        for child in node.get("children", []):
            walk_rerun(child, bundle)

    for node in rerun_tree.get("testNodes", []):
        walk_rerun(node, None)

    whole_targets = set()
    for failure in orig_failures:
        ident = failure.get("testIdentifierString", "")
        if "/" not in ident and failure.get("targetName"):
            whole_targets.add(failure["targetName"])

    def update_orig(node, bundle):
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            bundle = node.get("name")
            if bundle in whole_targets and bundle in rerun_bundles:
                node["children"] = copy.deepcopy(rerun_bundles[bundle].get("children", []))
                return
        if node.get("nodeType") == "Test Case" and bundle:
            ident = normalize_id(node.get("nodeIdentifier") or node.get("name"))
            replacement = rerun_cases_by_bundle.get(bundle, {}).get(ident)
            if replacement is not None:
                node["result"] = replacement.get("result", node.get("result"))
        for child in node.get("children", []):
            update_orig(child, bundle)

    existing_bundles = {
        n.get("name") for n in merged.get("testNodes", []) if n.get("nodeType") in ("Unit test bundle", "UI test bundle")
    }
    for target in whole_targets:
        if target in rerun_bundles and target not in existing_bundles:
            merged.setdefault("testNodes", []).append(copy.deepcopy(rerun_bundles[target]))

    for node in merged.get("testNodes", []):
        update_orig(node, None)

    return merged


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--stamp", required=True)
    args = parser.parse_args(argv)

    repo = pathlib.Path(args.repo).resolve()
    run_dir = pathlib.Path(args.run_dir).resolve()
    stamp = args.stamp

    meta_path = run_dir / "run-meta.json"
    orig_summary_path = run_dir / "tests-summary.json"
    orig_tree_path = run_dir / "tests-tree.json"
    rerun_summary_path = run_dir / f"rerun-{stamp}-summary.json"
    rerun_tree_path = run_dir / f"rerun-{stamp}-tree.json"

    for required in (meta_path, orig_summary_path, orig_tree_path, rerun_summary_path, rerun_tree_path):
        if not required.is_file():
            print(f"reconcile refused: missing {required.name}", file=sys.stderr)
            return 1

    meta = json.loads(meta_path.read_text())
    if meta.get("dirty"):
        print("reconcile refused: original verify run was on a dirty working tree", file=sys.stderr)
        return 1

    status_proc = subprocess.run(
        ["git", "status", "--porcelain", "-uno"], cwd=repo, capture_output=True, text=True, check=False
    )
    if status_proc.returncode != 0 or status_proc.stdout.strip():
        print("reconcile refused: working tree has uncommitted changes", file=sys.stderr)
        return 1

    tree_proc = subprocess.run(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=repo, capture_output=True, text=True, check=False
    )
    commit_proc = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True, check=False
    )
    current_tree = tree_proc.stdout.strip()
    current_commit = commit_proc.stdout.strip()
    if not current_tree or current_tree != meta.get("tree"):
        print(
            f"reconcile refused: current HEAD^{{tree}} ({current_tree[:12]}) does not match run tree ({str(meta.get('tree', ''))[:12]})",
            file=sys.stderr,
        )
        return 1

    steps = meta.get("steps") or []
    if not steps:
        print("reconcile refused: run-meta.json has no recorded steps", file=sys.stderr)
        return 1
    for step in steps:
        name = step.get("name", "")
        status = step.get("status", "")
        if name not in TEST_STEP_NAMES and status != "PASS":
            print(f"reconcile refused: non-test step failed: {name} ({status})", file=sys.stderr)
            return 1

    rerun_summary = json.loads(rerun_summary_path.read_text())
    if rerun_summary.get("failedTests", 0) != 0 or (rerun_summary.get("testFailures") or []):
        print("reconcile refused: rerun still has test failures", file=sys.stderr)
        return 1

    orig_summary = json.loads(orig_summary_path.read_text())
    orig_failures = orig_summary.get("testFailures") or []
    orig_tree = json.loads(orig_tree_path.read_text())
    rerun_tree = json.loads(rerun_tree_path.read_text())

    merged_tree = merge_test_trees(orig_tree, rerun_tree, orig_failures)
    merged_cases = {
        (bundle, normalize_id(ident)): result for bundle, ident, result in verify_judge.collect_cases(merged_tree)
    }
    for failure in orig_failures:
        target = failure.get("targetName", "")
        ident = failure.get("testIdentifierString", "")
        if "/" in ident:
            if merged_cases.get((target, normalize_id(ident))) != "Passed":
                print(f"reconcile refused: {target}/{ident} did not pass in merged results", file=sys.stderr)
                return 1

    _, problems = verify_judge.judge_hosted(
        merged_tree,
        includes_ui=not bool(meta.get("skip_ui", False)),
        includes_snapshots=bool(meta.get("runs_snapshots", False)),
    )
    if problems:
        for problem in problems:
            print(f"reconcile refused: {problem}", file=sys.stderr)
        return 1

    build_dir = repo / ".build"
    build_dir.mkdir(parents=True, exist_ok=True)
    receipt_path = build_dir / "verify-receipt.json"
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    full_gate = bool(meta.get("full_gate", False)) and not bool(meta.get("scoped", False))
    payload = {
        "tree": current_tree,
        "commit": current_commit,
        "dirty": False,
        "full_gate": full_gate,
        "reconciled": True,
        "reconciled_from": str(meta.get("run", "")),
        "rerun_stamp": stamp,
        "result": "PASS",
        "run": str(meta.get("run", "")),
        "timestamp": timestamp,
    }
    receipt_path.write_text(json.dumps(payload, indent=2) + "\n")
    if full_gate and current_commit:
        subprocess.run(
            ["git", "notes", "--ref=verify", "add", "-f", "-F", str(receipt_path), "HEAD"],
            cwd=repo,
            capture_output=True,
            check=False,
        )
    print(f"reconciled verify receipt written: run={payload['run']} rerun={stamp} tree={current_tree[:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
