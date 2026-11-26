#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs Pesto's headless-safe CPU, memory, and latency benchmarks and checks results against scripts/bench-thresholds.json.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

MODE="${PESTO_BENCH_MODE:-$([[ -n "${CI:-}" || -n "${PESTO_CI:-}" ]] && echo ci || echo local)}"
OUT_DIR=".build/benchmarks"
mkdir -p "$OUT_DIR"
CORE_LOG="$OUT_DIR/core-perf.log"
HOSTED_LOG="$OUT_DIR/hosted-perf.log"
PROFILE_LOG="$OUT_DIR/profile-budget.log"

: > "$CORE_LOG"
: > "$HOSTED_LOG"
: > "$PROFILE_LOG"

suite_status=0

echo "==> Running Core performance tests (mode=$MODE)..."
if ! PESTO_SYNC_PERF_CLIPS="${PESTO_SYNC_PERF_CLIPS:-2000}" \
  swift test --no-parallel -Xswiftc -O --filter "SyncPerformanceTests|SimilarityPerformanceTests|WidgetSnapshotPerformanceTests" \
  > "$CORE_LOG" 2>&1; then
  tail -40 "$CORE_LOG" >&2 || true
  suite_status=1
fi

echo "==> Generating Xcode project and running hosted performance tests..."
make generate >/dev/null
if ! xcodebuild \
  -project Pesto.xcodeproj \
  -scheme Pesto \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -only-testing:PestoTests/WatcherPerformanceTests \
  -only-testing:PestoTests/LargeHistoryPerformanceTests \
  -only-testing:PestoTests/HostedGlobals/PasteWritePerformanceTests \
  -only-testing:PestoTests/HostedGlobals/HoverCardPerformanceTests \
  -only-testing:PestoTests/HistoryMemoryTests \
  -only-testing:PestoTests/OverlayPerformanceTests \
  -only-testing:PestoTests/IngestPipelinePerformanceTests \
  test > "$HOSTED_LOG" 2>&1; then
  tail -40 "$HOSTED_LOG" >&2 || true
  suite_status=1
fi

if [[ "${PESTO_BENCH_SKIP_PROFILE:-0}" != "1" ]] && command -v footprint >/dev/null 2>&1; then
  echo "==> Running Profile steady-state memory and idle CPU checks..."
  scripts/check-memory-budget.sh >> "$PROFILE_LOG" 2>&1 || suite_status=1
  PESTO_SKIP_PROFILE_BUILD=1 scripts/check-memory-budget.sh --idle-cpu >> "$PROFILE_LOG" 2>&1 || suite_status=1
else
  echo "Skipping Profile memory/idle-cpu checks (PESTO_BENCH_SKIP_PROFILE=${PESTO_BENCH_SKIP_PROFILE:-0})."
fi

REPORT_ARGS=(
  "$CORE_LOG"
  "$HOSTED_LOG"
  "$PROFILE_LOG"
  --mode "$MODE"
  --thresholds scripts/bench-thresholds.json
  --json-out "$OUT_DIR/report.json"
)
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  REPORT_ARGS+=(--summary-out "$GITHUB_STEP_SUMMARY")
fi

report_status=0
python3 scripts/bench_report.py "${REPORT_ARGS[@]}" || report_status=$?

if [[ "$suite_status" -ne 0 || "$report_status" -ne 0 ]]; then
  exit 1
fi
