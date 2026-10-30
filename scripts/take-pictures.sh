#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Retakes every picture of the README, the guide and the website from one build, without the full gate:
# the documentation screenshots into docs/images, the website screenshots into .build/marketing, and the app commit
# into docs/images/SOURCE and .build/marketing/SOURCE. Run by `make pictures`; docs/pictures.md is the map.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if pgrep -x Pesto >/dev/null; then
  echo "take-pictures.sh: Pesto is running. Quit it and run this again." >&2
  exit 2
fi

run="$(date +%Y%m%d-%H%M%S)"
shots=".build/ui-screenshots/$run"
raw=".build/pictures/$run"
result="$raw/doc.xcresult"
mkdir -p "$raw" "$shots"

xcodebuild_test() {
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    "$@" test
}

# A failing test must not stop the pictures that were taken from being exported; the run still ends with its status.
status=0
doc_suites=(DocScreenshotTests SnippetSuggestionsTests ShortcutRecordingTests SettingsFlowTests AboutWindowTests
  HistoryLockTests OnboardingAndStatesTests ThemeSettingsTests)
only=()
for suite in "${doc_suites[@]}"; do only+=("-only-testing:PestoUITests/$suite"); done
TEST_RUNNER_PESTO_SCREENSHOT_DIR="$PWD/$shots" xcodebuild_test "${only[@]}" -resultBundlePath "$result" \
  >"$raw/doc.log" 2>&1 || status=$?

xcrun xcresulttool export attachments --path "$result" --output-path "$raw/attachments" >/dev/null 2>&1 || true
python3 - "$raw/attachments" "$shots" <<'PY'
import json, os, re, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    test_name = re.sub(r"[^A-Za-z0-9_]", "", test.get("testIdentifier", "test").split("/")[-1])
    for att in test.get("attachments", []):
        name = att.get("suggestedHumanReadableName", "")
        src = os.path.join(raw, att["exportedFileName"])
        if not src.endswith(".png") or name.startswith(("Debug description", "App UI hierarchy", "UI Snapshot")):
            continue
        os.makedirs(os.path.join(out, test_name), exist_ok=True)
        shutil.copyfile(src, os.path.join(out, test_name, re.sub(r"_0_[0-9A-F-]{36}(\.\w+)?$", "", name) + ".png"))
PY
rm -rf "$raw/attachments"
scripts/export-doc-images.sh "$shots"
swift scripts/make-installer-image.swift

# The marketing run is last so that export-marketing-images.sh finds it as the newest result.
xcodebuild_test -only-testing:PestoUITests/MarketingScreenshotTests >"$raw/marketing.log" 2>&1 || status=$?
scripts/export-marketing-images.sh

stamp="commit $(git rev-parse HEAD)"
[[ -z "$(git status --porcelain --untracked-files=no -- Sources Tests Pesto.yml)" ]] || stamp="$stamp dirty"
echo "$stamp" > docs/images/SOURCE
echo "$stamp" > .build/marketing/SOURCE
echo "pictures taken from $stamp (logs in $raw)"
exit "$status"
