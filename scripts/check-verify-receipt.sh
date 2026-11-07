#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verifies that the full verification gate (make verify) passed on the exact tree being released.
# Matching on HEAD^{tree} (with a clean working tree) means a PR branch that passed make verify and was
# squash-merged onto main without content changes keeps its valid proof without needing a second 1-hour run.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_DIR="$2"
      shift 2
      ;;
    --receipt)
      RECEIPT_PATH="$2"
      shift 2
      ;;
    *)
      echo "usage: $0 [--repo <dir>] [--receipt <file>]" >&2
      exit 2
      ;;
  esac
done

cd "$REPO_DIR"
[[ -z "$RECEIPT_PATH" ]] && RECEIPT_PATH="$REPO_DIR/.build/verify-receipt.json"

if [[ "${PESTO_SKIP_VERIFY_RECEIPT:-}" == "1" ]]; then
  echo "warning: PESTO_SKIP_VERIFY_RECEIPT=1 set; skipping full-gate verification receipt check." >&2
  exit 0
fi

if [[ -n "$(git status --porcelain -uno)" ]]; then
  echo "error: working tree has uncommitted changes. Commit all changes and run 'make verify' before releasing." >&2
  exit 1
fi

CURRENT_TREE="$(git rev-parse 'HEAD^{tree}')"
CURRENT_COMMIT="$(git rev-parse HEAD)"

RECEIPT_JSON=""
if [[ -f "$RECEIPT_PATH" ]]; then
  RECEIPT_JSON="$(cat "$RECEIPT_PATH")"
fi

NOTE_JSON="$(git notes --ref=verify show HEAD 2>/dev/null || true)"

python3 - "$CURRENT_TREE" "$CURRENT_COMMIT" "$RECEIPT_JSON" "$NOTE_JSON" <<'PY'
import json
import subprocess
import sys

current_tree, current_commit, file_raw, note_raw = sys.argv[1:5]

candidates = []
for source, raw in [("receipt file (.build/verify-receipt.json)", file_raw), ("git note (refs/notes/verify)", note_raw)]:
    if not raw.strip():
        continue
    try:
        candidates.append((source, json.loads(raw)))
    except Exception:
        continue

if not candidates:
    print(
        "error: no full-gate verification receipt found (.build/verify-receipt.json or refs/notes/verify).\n"
        "       Run 'make verify' on this commit before building a release.",
        file=sys.stderr,
    )
    sys.exit(1)

reasons = []
for source, data in candidates:
    if data.get("result") != "PASS":
        reasons.append(f"{source}: result is {data.get('result')!r}, expected 'PASS'")
        continue
    if not data.get("full_gate"):
        reasons.append(f"{source}: gate ran with --fast or --no-ui; release requires full 'make verify'")
        continue
    if data.get("dirty"):
        reasons.append(f"{source}: gate ran on a dirty working tree; release requires a clean tree")
        continue
    recorded_tree = data.get("tree", "")
    if recorded_tree != current_tree:
        rec_commit = data.get("commit", "")
        code_diff = subprocess.run(
            ["git", "diff", "--name-only", rec_commit, current_commit, "--", "Sources", "Tests", "Package.resolved"],
            capture_output=True,
            text=True,
        ).stdout.strip()
        if not rec_commit or code_diff:
            reasons.append(
                f"{source}: recorded tree {recorded_tree[:12]} does not match HEAD^{{tree}} {current_tree[:12]}"
            )
            continue
    print(
        f"✓ Release verify receipt valid ({source}): "
        f"run={data.get('run', '?')} timestamp={data.get('timestamp', '?')} "
        f"tree={current_tree[:12]} commit={data.get('commit', current_commit)[:12]}"
    )
    sys.exit(0)

print("error: full-gate verification receipt does not match the current release tree:", file=sys.stderr)
for r in reasons:
    print(f"  - {r}", file=sys.stderr)
print("  Run 'make verify' on the clean release tree before packaging a release.", file=sys.stderr)
sys.exit(1)
PY
