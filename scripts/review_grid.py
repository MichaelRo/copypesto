#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Map changed files onto Pesto's scoped multi-agent review grid and run fast static guards."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
from typing import Any

LENSES: list[dict[str, Any]] = [
    {
        "id": "core-concurrency",
        "title": "Core Architecture & Swift 6 Concurrency",
        "role": "Swift 6 Core Architect",
        "patterns": [r"^Sources/Core/", r"^Tests/PestoCoreTests/"],
        "invariants": [
            "Core/ must never import SwiftUI (CoreDirectoryCycleTests one-way graph).",
            "All Core types are Sendable; avoid @unchecked Sendable shortcuts.",
            "Every Core/ bug fix follows TDD (failing test first) and uses runtime seams (AppDefaults, AppPasteboard, AppPaths).",
        ],
        "commands": ["DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PestoCoreTests"],
    },
    {
        "id": "security-crypto",
        "title": "Security, Cryptography & Privacy Boundaries",
        "role": "Security & Privacy Auditor",
        "patterns": [
            r"^Sources/Core/(Crypto|Security|Sync|Backup|Pasteboard)/",
            r"^Sources/CoreNetworking/",
            r"^Sources/.*\.entitlements$",
            r"^\.github/",
            r"^Tests/PestoRegressionTests/(NetworkGuard|OnDiskEncryption|Entitlements|PersonalData|ExtensionBinaryNetwork)Tests\.swift$",
        ],
        "invariants": [
            "No third-party analytics SDKs or unauthorized network endpoints (NetworkGuardTests).",
            "All clip payloads, previews (except validated colors), and metadata remain AES-GCM-256 sealed at rest.",
            "Exclusion rules stay append-only; concealed pasteboard markers are dropped; extension entitlements stay minimal.",
        ],
        "commands": [
            "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter \"NetworkGuardTests|EntitlementsTests|PersonalDataTests|OnDiskEncryptionTests\""
        ],
    },
    {
        "id": "macos-ui-a11y",
        "title": "macOS AppKit/SwiftUI, Motion & Accessibility",
        "role": "macOS Native UI & Accessibility Reviewer",
        "patterns": [
            r"^Sources/(App|Features|Shared|Controls|Widget)/",
            r"^Tests/(PestoTests|PestoSnapshotTests|PestoUITests)/",
        ],
        "invariants": [
            "Every NSHostingView must be SafeHostingView; never cast NSApp.delegate as? AppDelegate.",
            "Views use @Environment(\\.pestoAccent), Motion.animation(_:), and Localizable.xcstrings plurals.",
            "No raw glass-on-glass on cards; covered/secret cards expose no side doors (CardConcealment).",
        ],
        "commands": ["make lint", "make test"],
    },
    {
        "id": "ios-extensions",
        "title": "iOS App, Keyboard, AutoFill, Share & Widgets",
        "role": "iOS & Extension Boundary Reviewer",
        "patterns": [r"^Sources/Mobile", r"^Sources/Widget/", r"^Tests/PestoMobile"],
        "invariants": [
            "Extensions hold only scoped Keychain/App Group keys (never historyKey) and zero network calls.",
            "Keyboard search page letters never reach the host app; History Lock gates widgets/AutoFill/keyboard when off.",
            "Targets build cleanly for iOS Simulator via PestoMobileCITests.",
        ],
        "commands": ["make build-mobile", "make test-mobile"],
    },
    {
        "id": "perf-budgets",
        "title": "Performance, Memory & Latency Budgets",
        "role": "Systems Performance Benchmarker",
        "patterns": [
            r"^Sources/Core/(Storage|Imaging|Pasteboard|Search|Sync)/",
            r"^Sources/Features/Overlay/",
            r"^scripts/(bench|check-memory-budget)",
            r"^Tests/.*(Performance|Memory).*\.swift$",
            r"^docs/perf/",
        ],
        "invariants": [
            "Overlay open <100 ms, search <4 ms/keystroke, steady memory <150 MB, idle CPU <0.5%.",
            "No ModelContext.didSave observer with queue: .main (use ModelSaveObserver).",
            "Heavy decodes stay off SwiftUI body and bounded by PixelBudgets/ThumbnailCache.",
        ],
        "commands": ["make bench-ci"],
    },
    {
        "id": "tooling-ci-docs",
        "title": "Tooling, CI Workflows, ADRs & Docs Sync",
        "role": "Tooling, Shell Safety & Release Integrity Reviewer",
        "patterns": [
            r"^Makefile$",
            r"^Pesto\.yml$",
            r"^Package\.swift$",
            r"^scripts/",
            r"^\.github/",
            r"^\.githooks/",
            r"^decisions/",
            r"^docs/",
            r"^(AGENTS|README|CONTRIBUTING)\.md$",
        ],
        "invariants": [
            "Shell/Makefile scripts avoid unsafe quoting on user strings and guard destructive targets with require-dev-reset.",
            "GitHub Actions pin third-party actions to commit SHAs with minimal contents: read permissions.",
            "ADRs stay indexed and sorted in decisions/README.md; docs stay aligned with tooling.",
        ],
        "commands": [
            "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter PestoRegressionTests",
            "make lint",
        ],
    },
]

FORBIDDEN_SDKS = (
    "Sentry",
    "Mixpanel",
    "Amplitude",
    "Bugsnag",
    "Crashlytics",
    "Firebase",
    "Datadog",
    "Segment",
    "GoogleAnalytics",
    "PostHog",
    "Heap",
)
FORBIDDEN_FILE_PATTERNS = (r"\.key$", r"\.pem$", r"\.p12$", r"\.mobileprovision$", r"\.DS_Store$")


def changed_files_from_git(base: str | None, staged: bool) -> list[str]:
    if staged:
        cmd = ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"]
    elif base:
        merge_base = subprocess.check_output(["git", "merge-base", base, "HEAD"], text=True).strip()
        cmd = ["git", "diff", "--name-only", "--diff-filter=ACMR", merge_base]
    else:
        cmd = ["git", "diff", "--name-only", "--diff-filter=ACMR", "HEAD"]
    out = subprocess.check_output(cmd, text=True)
    files = [line.strip() for line in out.splitlines() if line.strip()]
    if not staged:
        status = subprocess.check_output(["git", "status", "--porcelain"], text=True)
        for line in status.splitlines():
            if line.startswith("?? "):
                files.append(line[3:].strip())
    return sorted(set(files))


def build_grid(files: list[str]) -> list[dict[str, Any]]:
    triggered: list[dict[str, Any]] = []
    for lens in LENSES:
        compiled = [re.compile(p) for p in lens["patterns"]]
        matched = [f for f in files if any(rx.search(f) for rx in compiled)]
        if matched:
            prompt = (
                f"You are the {lens['role']}. Review ONLY these changed files sequentially:\n"
                + "\n".join(f"- {f}" for f in matched)
                + "\nCheck these invariants:\n"
                + "\n".join(f"- {inv}" for inv in lens["invariants"])
                + "\nReport concrete defects with file:line citations or state CLEAN."
            )
            triggered.append(
                {
                    "id": lens["id"],
                    "title": lens["title"],
                    "role": lens["role"],
                    "files": matched,
                    "invariants": lens["invariants"],
                    "commands": lens["commands"],
                    "prompt": prompt,
                }
            )
    return triggered


def run_static_checks(files: list[str], root: pathlib.Path) -> list[str]:
    violations: list[str] = []
    for rel in files:
        for pat in FORBIDDEN_FILE_PATTERNS:
            if re.search(pat, rel, re.IGNORECASE):
                violations.append(f"Forbidden file pattern ({pat}): {rel}")
        path = root / rel
        if not path.is_file() or not rel.endswith(".swift"):
            continue
        content = path.read_text(encoding="utf-8", errors="replace")
        if rel.startswith("Sources/Core/") and re.search(r"^\s*import\s+SwiftUI\b", content, re.MULTILINE):
            violations.append(f"Module boundary violation: {rel} imports SwiftUI inside Core/")
        for sdk in FORBIDDEN_SDKS:
            if re.search(rf"\b(import|@import)\s+{sdk}\b", content):
                violations.append(f"Forbidden analytics SDK ({sdk}) imported in: {rel}")
        if rel.startswith("Sources/") and not rel.startswith("Sources/CLI/"):
            if "UserDefaults.standard" in content:
                violations.append(f"Runtime seam bypass: UserDefaults.standard in {rel}")
            if "NSPasteboard.general" in content and not rel.startswith("Sources/Core/Paste/"):
                violations.append(f"Runtime seam bypass: NSPasteboard.general in {rel}")
    return violations


def render_markdown(files: list[str], grid: list[dict[str, Any]]) -> str:
    if not files:
        return "## Scoped Multi-Agent Review Grid\n\nNo changed files detected.\n"
    if not grid:
        return "## Scoped Multi-Agent Review Grid\n\nChanged files did not trigger any review lens.\n"
    lines = ["## Scoped Multi-Agent Review Grid", ""]
    lines.append("| Lens | Role | Matched Files | Verification |")
    lines.append("|---|---|---|---|")
    for cell in grid:
        cmds = ", ".join(f"`{c}`" for c in cell["commands"])
        lines.append(f"| `{cell['id']}` | {cell['role']} | {len(cell['files'])} | {cmds} |")
    lines.append("")
    for cell in grid:
        lines.append(f"### {cell['title']} (`{cell['id']}`)")
        lines.append("Files: " + ", ".join(f"`{f}`" for f in cell["files"]))
        lines.append("Invariants:")
        for inv in cell["invariants"]:
            lines.append(f"- {inv}")
        lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build Pesto's scoped multi-agent review grid.")
    parser.add_argument("--base", help="Compare against git base ref (e.g. origin/main).")
    parser.add_argument("--staged", action="store_true", help="Inspect staged changes.")
    parser.add_argument("--files", nargs="*", help="Explicit list of relative file paths.")
    parser.add_argument("--json", action="store_true", help="Emit JSON output.")
    parser.add_argument("--check", action="store_true", help="Run fast static diff guards and fail on violations.")
    args = parser.parse_args(argv)

    if args.files is not None:
        files = sorted(set(args.files))
    else:
        files = changed_files_from_git(args.base, args.staged)

    grid = build_grid(files)
    if args.json:
        print(json.dumps({"files": files, "lenses": grid}, indent=2))
    else:
        print(render_markdown(files, grid))

    if args.check:
        violations = run_static_checks(files, pathlib.Path(os.getcwd()))
        if violations:
            for item in violations:
                sys.stderr.write(f"review-grid: {item}\n")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
