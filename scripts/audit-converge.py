#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
Audit working tree and git diff against Pesto's SDD and Harness Engineering invariants.
Runs before concluding tasks to ensure:
1. No uncommitted secret files (*.key, *.pem, *.p12, *.mobileprovision) accidentally added.
2. No third-party analytics SDK strings introduced.
3. No module boundary violations (e.g., Core/ importing SwiftUI).
4. No direct UserDefaults.standard or NSPasteboard.general bypasses in Core/Features.
"""

import os
import re
import subprocess
import sys

FORBIDDEN_SDKS = [
    "Sentry", "Mixpanel", "Amplitude", "Bugsnag", "Crashlytics",
    "Firebase", "Datadog", "Segment", "GoogleAnalytics", "PostHog", "Heap"
]

FORBIDDEN_FILE_PATTERNS = [
    r"\.key$", r"\.pem$", r"\.p12$", r"\.mobileprovision$", r"\.DS_Store$"
]

def get_changed_files():
    try:
        # Check staged and unstaged files
        cmd = ["git", "diff", "--name-only", "HEAD"]
        output = subprocess.check_output(cmd, text=True).strip()
        files = [line.strip() for line in output.splitlines() if line.strip()]
        
        # Also check untracked files
        untracked = subprocess.check_output(["git", "status", "--porcelain"], text=True).strip()
        for line in untracked.splitlines():
            if line.startswith("?? "):
                files.append(line[3:].strip())
        return list(set(files))
    except Exception as e:
        print(f"Error reading git status: {e}", file=sys.stderr)
        sys.exit(1)

def audit():
    print("🔍 Running Pesto SDD Convergence & Diff Audit...")
    changed = get_changed_files()
    if not changed:
        print("✅ Clean working tree. No uncommitted changes.")
        return

    violations = []

    # 1. Check for sensitive or forbidden file extensions
    for f in changed:
        for pattern in FORBIDDEN_FILE_PATTERNS:
            if re.search(pattern, f, re.IGNORECASE):
                violations.append(f"Forbidden file pattern ({pattern}): {f}")

    # 2. Check Swift files for architectural invariant violations
    swift_files = [f for f in changed if f.endswith(".swift") and os.path.exists(f)]
    for f in swift_files:
        with open(f, "r", encoding="utf-8", errors="ignore") as fh:
            content = fh.read()

        # Core/ must not import SwiftUI
        if f.startswith("Sources/Core/") and re.search(r"^\s*import\s+SwiftUI\b", content, re.MULTILINE):
            violations.append(f"Module boundary violation: {f} imports SwiftUI inside Core/")

        # No forbidden analytics SDKs
        for sdk in FORBIDDEN_SDKS:
            if re.search(rf"\b(import|@import)\s+{sdk}\b", content):
                violations.append(f"Forbidden analytics SDK ({sdk}) imported in: {f}")

        # Check for direct UserDefaults.standard or NSPasteboard.general in production code
        if f.startswith("Sources/") and not f.startswith("Sources/CLI/"):
            if "UserDefaults.standard" in content:
                violations.append(f"Runtime seam bypass: UserDefaults.standard used in {f} (use AppDefaults.store)")
            if "NSPasteboard.general" in content and not f.startswith("Sources/Core/Paste/"):
                violations.append(f"Runtime seam bypass: direct NSPasteboard.general used in {f} (use AppPasteboard.general)")

    if violations:
        print("❌ SDD Convergence Audit FAILED with the following violations:", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        sys.exit(1)

    print("✅ Convergence audit passed: all modified files respect Pesto SDD invariants.")

if __name__ == "__main__":
    audit()
