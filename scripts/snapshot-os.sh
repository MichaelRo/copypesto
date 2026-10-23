#!/bin/bash
# SPDX-License-Identifier: MIT
# Says whether this Mac can run the card snapshots: they are pictures drawn by one macOS version and only comparable on
# it. Prints "match", or "snapshots skipped: baselines are macOS NN, this Mac is macOS MM" and exits 1.
# PESTO_SNAPSHOT_HOST_MAJOR stands in for the Mac's version in a test. Re-recording on a new macOS is deliberate:
# set PESTO_SNAPSHOT_OS_OVERRIDE=1 (make test-snapshots does when asked) and update Tests/PestoSnapshotTests/baseline-macos
# in the same pull request (docs/testing.md, "Card snapshots").
set -u
cd "$(dirname "$0")/.." || exit 2
baseline="$(tr -d '[:space:]' <Tests/PestoSnapshotTests/baseline-macos 2>/dev/null)"
host="${PESTO_SNAPSHOT_HOST_MAJOR:-$(sw_vers -productVersion | cut -d. -f1)}"
if [[ -z "$baseline" ]]; then
  echo "snapshots skipped: Tests/PestoSnapshotTests/baseline-macos is missing"
  exit 1
fi
if [[ -n "${CI:-}" || -n "${PESTO_CI:-}" ]]; then
  echo "snapshots skipped: a hosted runner draws them differently from the Mac that recorded them"
  exit 1
fi
if [[ "$baseline" == "$host" ]]; then
  echo "match: baselines and this Mac are macOS $host"
  exit 0
fi
echo "snapshots skipped: baselines are macOS $baseline, this Mac is macOS $host"
exit 1
