#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Pesto verification gate: lint, Core tests, Debug build, hosted tests, UI tests + screenshots.
# Prints a pass/fail summary and exits non-zero if any step fails.
#
#   scripts/verify.sh           everything (UI tests take a few minutes and drive real windows)
#   scripts/verify.sh --fast    lint + Core tests + build only (no Release build, no hosted or UI tests)
#   scripts/verify.sh --no-ui   everything except the UI tests (what CI runs; hosted PestoTests still run)
#
# Screenshots of the app's own windows land in .build/ui-screenshots/<run>/<Test>/<step>.png.
# One-time machine setup for the UI tests: docs/testing.md.

set -uo pipefail
cd "$(dirname "$0")/.."

# A sleeping display hangs the UI tests, so the whole run holds the Mac awake.
if [[ -z "${VERIFY_CAFFEINATED:-}" ]] && command -v caffeinate >/dev/null; then
  exec env VERIFY_CAFFEINATED=1 caffeinate -dis "$0" "$@"
fi

FAST=0
SKIP_UI=0
[[ "${1:-}" == "--fast" ]] && FAST=1
[[ "${1:-}" == "--no-ui" ]] && SKIP_UI=1

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# A running Pesto answers for the tests' windows and makes some of them skip, so the gate will not start next to one.
if [[ $FAST -eq 0 ]] && pgrep -x Pesto >/dev/null; then
  echo "verify.sh: Pesto is running. Quit it (menu bar icon > Quit Pesto) and run this again." >&2
  exit 2
fi

RUN="$(date +%Y%m%d-%H%M%S)"
LOGS=".build/verify/$RUN"
SHOTS=".build/ui-screenshots/$RUN"
DERIVED=".build/xcode"
mkdir -p "$LOGS"

NAMES=()
STATUS=()
DETAIL=()
SECONDS_TOTAL=$SECONDS

record() {
  NAMES+=("$1"); STATUS+=("$2"); DETAIL+=("$3")
  printf '  %-4s  %-36s %s\n' "$2" "$1" "$((SECONDS - SECONDS_TOTAL)) s"
}

step_lint() {
  if make lint >"$LOGS/lint.log" 2>&1; then
    record "lint" "PASS" "$(grep -E 'Found [0-9]+ violations' "$LOGS/lint.log" | tail -1 | sed 's/^Done linting! //')"
  else
    record "lint" "FAIL" "$(grep -E '(error|warning):' "$LOGS/lint.log" | head -3 | tr '\n' ' ')"
  fi
}

# Warnings in this repository's own Swift files. SWIFT_TREAT_WARNINGS_AS_ERRORS does not turn Swift 6's isolation
# diagnostics into errors (four of them built green until 2026-10-04), so the log is read instead.
project_warnings() {
  grep -E "^$PWD/(Sources|Tests)/[^:]+:[0-9]+:[0-9]+: warning:" "$1" | sed "s|$PWD/||" | sort -u
}

step_core() {
  swift test >"$LOGS/core.log" 2>&1
  local code=$?
  sed -i '' 's/\x1b\[[0-9;]*m//g' "$LOGS/core.log"
  local warnings
  warnings="$(project_warnings "$LOGS/core.log")"
  [[ -n "$warnings" ]] && record "core build warnings" "FAIL" "$(echo "$warnings" | wc -l | tr -d ' ') warnings: $(echo "$warnings" | head -3 | cut -c1-120 | tr '\n' ' ')"
  local judged judged_code
  judged="$(python3 scripts/verify_judge.py core "$LOGS/core.log")"
  judged_code=$?
  if [[ $code -ne 0 ]]; then
    sed 's/\x1b\[[0-9;]*m//g' "$LOGS/core.log" | grep -E '✘ Test .* recorded an issue|error:' | cut -c1-240 >>"$LOGS/failures.txt"
    record "core tests" "FAIL" "$(sed 's/\x1b\[[0-9;]*m//g' "$LOGS/core.log" | grep -E '✘|error:' | head -3 | tr '\n' ' ')"
  elif [[ $judged_code -ne 0 ]]; then
    record "core tests" "FAIL" "$(echo "$judged" | tr '\n' ' ')"
  else
    record "core tests" "PASS" "$judged"
  fi
}

step_build() {
  local warnings
  if make build >"$LOGS/build.log" 2>&1; then
    warnings="$(project_warnings "$LOGS/build.log")"
    if [[ -n "$warnings" ]]; then
      record "build (Debug, warnings as errors)" "FAIL" "$(echo "$warnings" | wc -l | tr -d ' ') warnings: $(echo "$warnings" | head -3 | cut -c1-120 | tr '\n' ' ')"
    else
      record "build (Debug, warnings as errors)" "PASS" ""
    fi
  else
    record "build (Debug, warnings as errors)" "FAIL" "$(grep -E '^/.*error:' "$LOGS/build.log" | sort -u | head -3 | tr '\n' ' ')"
  fi
}

step_release_build() {
  if scripts/check-release-build.sh >"$LOGS/release.log" 2>&1; then
    record "release build (hardened runtime)" "PASS" "$(tail -1 "$LOGS/release.log" | cut -c1-90)"
  else
    record "release build (hardened runtime)" "FAIL" "$(grep -E 'error:|check-release-build' "$LOGS/release.log" | sort -u | head -3 | tr '\n' ' ')"
  fi
}

# The memory budget in AGENTS.md, measured on a Profile build (Release with test hooks) showing the shelf over the
# 5,000-clip history. Needs a window server, so it is skipped with --no-ui.
step_memory() {
  if scripts/check-memory-budget.sh >"$LOGS/memory.log" 2>&1; then
    record "memory budget" "PASS" "$(grep -m1 '^memory:' "$LOGS/memory.log" | cut -c1-110)"
  else
    record "memory budget" "FAIL" "$(grep -E '^memory:|check-memory-budget' "$LOGS/memory.log" | head -2 | tr '\n' ' ')"
  fi
}

# The same budget with 300 large pictures scrolled through to the end (P-06): the thumbnail cache is what grows.
step_memory_pictures() {
  if scripts/check-memory-budget.sh 150 pictures >"$LOGS/memory-pictures.log" 2>&1; then
    record "memory budget, pictures" "PASS" "$(grep -m1 '^memory:' "$LOGS/memory-pictures.log" | cut -c1-110)"
  else
    record "memory budget, pictures" "FAIL" "$(grep -E '^memory:|check-memory-budget' "$LOGS/memory-pictures.log" | head -2 | tr '\n' ' ')"
  fi
}

# The UI-test runner app is protected by macOS once it has been launched, so it cannot be overwritten by
# the next build. Setting the old bundle aside (a rename in an unprotected directory) works.
set_stale_runner_aside() {
  local runner="$DERIVED/Build/Products/Debug/PestoUITests-Runner.app"
  if [[ -e "$runner" ]]; then
    mkdir -p .build/stale-runners
    mv "$runner" ".build/stale-runners/PestoUITests-Runner-$RUN.app"
  fi
}

# A test that fails only because its host process died ("Test crashed with signal …") is re-run once, alone. If every
# failure of the run is such a crash and every one passes on its own, the gate passes and says which tests crashed;
# an assertion failure, or a second crash, is never forgiven. Prints the note and returns 0 when forgiven.
retry_host_crashes() {
  local summary="$1" failures
  failures="$(python3 scripts/verify_failures.py "$summary" 2>/dev/null)"
  [[ -n "$failures" ]] || return 1
  [[ -z "$(grep -v 'Test crashed with signal' <<<"$failures")" ]] || return 1
  local only=()
  while IFS= read -r argument; do only+=("$argument"); done < <(python3 scripts/verify_failures.py "$summary" --only-testing)
  [[ ${#only[@]} -gt 0 ]] || return 1
  local retry="$LOGS/crash-retry.xcresult"
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    "${only[@]}" -resultBundlePath "$retry" test >"$LOGS/crash-retry.log" 2>&1 || return 1
  echo "host crashed and passed on retry: $(sed 's/: Test crashed.*//' <<<"$failures" | tr '\n' ' ')(concurrent.log)"
}

step_hosted_and_ui() {
  UI_SKIP_ARGS=()
  TEST_LABEL="hosted + UI tests"
  if [[ $SKIP_UI -eq 1 ]]; then
    UI_SKIP_ARGS=(-skip-testing:PestoUITests)
    TEST_LABEL="hosted tests (UI skipped)"
  fi
  make generate >"$LOGS/generate.log" 2>&1
  # The card pictures are only comparable on the macOS that drew them: run them there, say so when they are skipped.
  SNAP_SKIP_ARGS=(-skip-testing:PestoSnapshotTests)
  RUNS_SNAPSHOTS=0
  local snapshot_note
  if snapshot_note="$(scripts/snapshot-os.sh)"; then
    SNAP_SKIP_ARGS=()
    RUNS_SNAPSHOTS=1
  fi
  set_stale_runner_aside
  # `caffeinate -dis` keeps a display awake but does not wake one that is already asleep, and OverlayPerformanceTests
  # hangs against a sleeping display; -u declares user activity, which does.
  caffeinate -u -t 3 2>/dev/null || true
  local result="$LOGS/tests.xcresult"
  # Ad-hoc signing: an unsigned test runner is killed on launch. The app needs no entitlements, so no
  # Apple account or provisioning profile is needed.
  # xcodebuild forwards TEST_RUNNER_* variables to the test process (a plain CI variable does not reach the app host).
  local ci_flag=()
  [[ -n "${CI:-}" ]] && ci_flag=(TEST_RUNNER_PESTO_CI=1)
  # A test host that dies of SIGTERM mid-run (2026-10-15, twice in 15 s) left no trace of what else was running:
  # sample the build and test processes so the next one can be matched against what was running (concurrent.log).
  ( while true; do
      { date '+%H:%M:%S'; pgrep -fl 'xcodebuild|swift-build|swift-frontend|bench-latency|Pesto' | cut -c1-140; } >>"$LOGS/concurrent.log"
      sleep 5
    done ) &
  local sampler=$!
  env ${ci_flag[@]+"${ci_flag[@]}"} TEST_RUNNER_PESTO_SCREENSHOT_DIR="$PWD/$SHOTS" xcodebuild \
    -project Pesto.xcodeproj -scheme Pesto -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    ${SNAP_SKIP_ARGS[@]+"${SNAP_SKIP_ARGS[@]}"} \
    ${UI_SKIP_ARGS[@]+"${UI_SKIP_ARGS[@]}"} \
    -resultBundlePath "$result" \
    test >"$LOGS/tests.log" 2>&1
  local code=$?
  kill "$sampler" 2>/dev/null; wait "$sampler" 2>/dev/null

  local summary="$LOGS/tests-summary.json"
  xcrun xcresulttool get test-results summary --path "$result" --compact >"$summary" 2>/dev/null
  python3 scripts/verify_failures.py "$summary" >>"$LOGS/failures.txt" 2>/dev/null
  local crashed_note=""
  if [[ $code -ne 0 ]]; then
    if crashed_note="$(retry_host_crashes "$summary")"; then
      code=0
      grep -v 'Test crashed with signal' "$LOGS/failures.txt" >"$LOGS/failures.txt.kept" || true
      mv "$LOGS/failures.txt.kept" "$LOGS/failures.txt"
    else
      crashed_note=""
    fi
  fi

  python3 - "$summary" "$LOGS/tests.log" <<'PY' >"$LOGS/tests-parsed.txt"
import json, re, sys
summary = json.load(open(sys.argv[1])) if sys.argv[1] else {}
log = open(sys.argv[2], errors="replace").read()
print("passed=%s failed=%s expected=%s skipped=%s" % (
    summary.get("passedTests", "?"), summary.get("failedTests", "?"),
    summary.get("expectedFailures", "?"), summary.get("skippedTests", "?")))
failures = summary.get("testFailures") or []
for f in failures[:8]:
    print("FAILED: %s: %s" % (f.get("testName", "?"), f.get("failureText", "")[:160]))
PY
  local tree="$LOGS/tests-tree.json" judged="" judged_code=0
  xcrun xcresulttool get test-results tests --path "$result" --compact >"$tree" 2>/dev/null
  judge_args=()
  [[ $SKIP_UI -eq 1 ]] && judge_args=(--no-ui)
  [[ $RUNS_SNAPSHOTS -eq 1 ]] && judge_args+=(--snapshots)
  judged="$(python3 scripts/verify_judge.py hosted "$tree" ${judge_args[@]+"${judge_args[@]}"} 2>&1)"
  judged_code=$?
  local parsed
  parsed="$(head -1 "$LOGS/tests-parsed.txt" 2>/dev/null)"
  local failed_lines
  failed_lines="$(grep '^FAILED:' "$LOGS/tests-parsed.txt" 2>/dev/null | head -3 | tr '\n' ' ')"

  local warnings
  warnings="$(project_warnings "$LOGS/tests.log")"
  if [[ -n "$warnings" ]]; then
    record "test build warnings" "FAIL" "$(echo "$warnings" | wc -l | tr -d ' ') warnings: $(echo "$warnings" | head -3 | cut -c1-120 | tr '\n' ' ')"
  fi

  if [[ $code -eq 0 && $judged_code -eq 0 ]]; then
    record "$TEST_LABEL" "PASS" "$parsed; $(echo "$judged" | head -1)${crashed_note:+; $crashed_note}"
  elif [[ $code -eq 0 ]]; then
    record "$TEST_LABEL" "FAIL" "$(echo "$judged" | tr '\n' ' ')"
  else
    record "$TEST_LABEL" "FAIL" "${parsed} ${failed_lines}"
  fi

  if [[ $RUNS_SNAPSHOTS -eq 1 ]]; then
    record "snapshots" "PASS" "$snapshot_note"
  else
    record "snapshots" "SKIP" "$snapshot_note"
  fi

  export_screenshots "$result"
}

export_screenshots() {
  local result="$1"
  local raw="$LOGS/attachments"
  mkdir -p "$raw" "$SHOTS"
  xcrun xcresulttool export attachments --path "$result" --output-path "$raw" >/dev/null 2>&1
  python3 - "$raw" "$SHOTS" <<'PY'
import json, os, re, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(raw, "manifest.json")))
count = 0
for test in manifest:
    test_name = re.sub(r"[^A-Za-z0-9_]", "", test.get("testIdentifier", "test").split("/")[-1])
    for att in test.get("attachments", []):
        name = att.get("suggestedHumanReadableName", "")
        # Keep our named PNG steps and failure dumps; skip system attachments (recordings, UI snapshots).
        if name.startswith(("Debug description", "App UI hierarchy", "UI Snapshot", "Screen Recording")):
            continue
        src = os.path.join(raw, att["exportedFileName"])
        step = re.sub(r"_0_[0-9A-F-]{36}(\.\w+)?$", "", name)
        ext = ".png" if src.endswith(".png") else ".txt" if src.endswith(".txt") else ""
        if not ext:
            continue
        dest_dir = os.path.join(out, test_name)
        os.makedirs(dest_dir, exist_ok=True)
        shutil.copyfile(src, os.path.join(dest_dir, step + ext))
        count += 1
print(count)
PY
  # The raw export includes a full-screen recording of the desktop; keep only the curated copies.
  find "$raw" -type f -delete
  find "$raw" -type d -empty -delete 2>/dev/null
}

step_lint
step_core
step_build
if [[ $FAST -eq 0 ]]; then
  step_release_build
  [[ $SKIP_UI -eq 0 ]] && step_memory
  [[ $SKIP_UI -eq 0 ]] && step_memory_pictures
  step_hosted_and_ui
fi

summarize() {
  echo
  echo "=== verify summary ($RUN) ==="
  for i in "${!NAMES[@]}"; do
    printf '%-4s  %-36s %s\n' "${STATUS[$i]}" "${NAMES[$i]}" "${DETAIL[$i]}"
  done
  if [[ $FAST -eq 1 ]]; then
    echo "SKIP  hosted + UI tests                (--fast)"
  elif [[ -d "$SHOTS" ]]; then
    echo "screenshots: $SHOTS ($(find "$SHOTS" -name '*.png' | wc -l | tr -d ' ') PNGs)"
  fi
  if [[ -s "$LOGS/failures.txt" ]]; then
    echo "failures: $LOGS/failures.txt ($(wc -l <"$LOGS/failures.txt" | tr -d ' ') lines); re-run only the failed tests: scripts/verify-rerun-failed.sh"
  fi
  echo "logs: $LOGS   elapsed: $((SECONDS - SECONDS_TOTAL)) s"
  if [[ $FAILED -eq 0 ]]; then echo "RESULT: PASS"; else echo "RESULT: FAIL"; fi
}

FAILED=0
for i in "${!NAMES[@]}"; do
  [[ "${STATUS[$i]}" == "FAIL" ]] && FAILED=1
done
summarize | tee "$LOGS/SUMMARY.txt"
exit $FAILED
