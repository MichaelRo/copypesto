#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Computes a changeset-scoped test execution plan for `scripts/verify.sh --scoped`.

    verify_scope.py [--repo <dir>] [--base <ref>] [--files <file> ...]

Prints a JSON object describing which test tiers to run (`run_core`, `core_filter`, `run_hosted`, `only_testing`,
`run_ui`, `run_snapshots`, `reason`).
"""
import argparse
import json
import pathlib
import subprocess
import sys


def git_changed_files(repo, base):
    files = set()
    diff_proc = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...HEAD"], cwd=repo, capture_output=True, text=True, check=False
    )
    if diff_proc.returncode == 0:
        files.update(line.strip() for line in diff_proc.stdout.splitlines() if line.strip())
    status_proc = subprocess.run(
        ["git", "status", "--porcelain", "-uno"], cwd=repo, capture_output=True, text=True, check=False
    )
    if status_proc.returncode == 0:
        for line in status_proc.stdout.splitlines():
            if len(line) > 3:
                path = line[3:].strip().split(" -> ")[-1]
                if path:
                    files.add(path)
    return sorted(files)


def compute_scope(changed_files):
    if not changed_files:
        return {
            "run_core": True,
            "core_filter": None,
            "run_hosted": False,
            "only_testing": [],
            "run_ui": False,
            "run_snapshots": False,
            "reason": "no changed files; running Core tests",
        }

    touches_core = False
    touches_features = False
    touches_grid = False
    touches_build_config = False
    core_test_names = set()
    hosted_suites = set()
    ui_suites = set()

    for path in changed_files:
        p = pathlib.PurePosixPath(path)
        stem = p.stem
        if path in ("Package.swift", "Package.resolved", "Pesto.yml", "Makefile") or path.endswith(".entitlements"):
            touches_build_config = True
        elif (
            path.startswith("Sources/Core/")
            or path.startswith("Tests/PestoCoreTests/")
            or path.startswith("Tests/PestoRegressionTests/")
            or path.startswith("scripts/")
        ):
            touches_core = True
            if stem.endswith("Tests"):
                core_test_names.add(stem)
            elif path.startswith("Sources/Core/") and p.suffix == ".swift":
                base_stem = stem.split("+")[0]
                core_test_names.add(f"{base_stem}Tests")
        elif path.startswith("Sources/Features/") or path.startswith("Sources/Shared/"):
            touches_features = True
            if "Features/Grid" in path or "Features/Overlay" in path or "ClipboardCard" in path or "Sources/Shared/" in path:
                touches_grid = True
                ui_suites.update([
                    "PestoUITests/OverlayFlowTests",
                    "PestoUITests/KeyboardNavigationTests",
                    "PestoUITests/SearchAndCollectionsTests",
                ])
            elif "Features/Settings" in path:
                ui_suites.update([
                    "PestoUITests/SettingsFlowTests",
                    "PestoUITests/ThemeSettingsTests",
                ])
            elif "Features/Onboarding" in path:
                ui_suites.add("PestoUITests/OnboardingAndStatesTests")
            else:
                ui_suites.add("PestoUITests/OverlayFlowTests")
        elif path.startswith("Tests/PestoTests/"):
            touches_features = True
            if stem.endswith("Tests"):
                hosted_suites.add(f"PestoTests/{stem}")
        elif path.startswith("Tests/PestoSnapshotTests/"):
            touches_features = True
            touches_grid = True
        elif path.startswith("Sources/App/"):
            touches_features = True
            ui_suites.update([
                "PestoUITests/OverlayFlowTests",
                "PestoUITests/PanelsAndMenuTests",
                "PestoUITests/SettingsFlowTests",
            ])
        elif path.startswith("Tests/PestoUITests/"):
            touches_features = True
            if stem.endswith("Tests"):
                ui_suites.add(f"PestoUITests/{stem}")

    if touches_build_config:
        return {
            "run_core": True,
            "core_filter": None,
            "run_hosted": True,
            "only_testing": ["PestoTests", "PestoUITests/OverlayFlowTests"],
            "run_ui": True,
            "run_snapshots": touches_grid,
            "reason": "build configuration changed",
        }

    run_core = touches_core or not touches_features
    core_filter = "|".join(sorted(core_test_names)) if (run_core and core_test_names) else None
    run_ui = bool(ui_suites)
    run_snapshots = touches_grid
    run_hosted = touches_features or run_ui or run_snapshots

    only_testing = []
    if run_hosted:
        if hosted_suites and not touches_grid and not run_ui:
            only_testing.extend(sorted(hosted_suites))
        else:
            only_testing.append("PestoTests")
        if run_snapshots:
            only_testing.append("PestoSnapshotTests")
        if run_ui:
            only_testing.extend(sorted(ui_suites))

    return {
        "run_core": run_core,
        "core_filter": core_filter,
        "run_hosted": run_hosted,
        "only_testing": only_testing,
        "run_ui": run_ui,
        "run_snapshots": run_snapshots,
        "reason": f"scoped to {len(changed_files)} changed file(s)",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".")
    parser.add_argument("--base", default="main")
    parser.add_argument("--files", nargs="*")
    args = parser.parse_args(argv)

    repo = pathlib.Path(args.repo).resolve()
    changed = args.files if args.files is not None else git_changed_files(repo, args.base)
    plan = compute_scope(changed)
    print(json.dumps(plan, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
