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
doc_suites=(DocScreenshotTests SnippetSuggestionsTests SettingsFlowTests AboutWindowTests
  HistoryLockTests OnboardingAndStatesTests ThemeSettingsTests ThemeShelfTests SettingsReorganisationTests)
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

# The App Store pictures of the iPhone and iPad app go to .build/app-store (docs/pictures.md): they are not in the README
# or the guide. A missing simulator or a failing run skips them, and the Mac pictures above stand.
store_pictures() {
  local name="$1" fallback_runtime_family="$2" udid
  udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in sorted(json.load(sys.stdin)["devices"].items(), reverse=True):
    for device in devices:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"]); raise SystemExit
' "$name")"
  if [[ -z "$udid" ]]; then
    local runtime type
    runtime="$(xcrun simctl list runtimes available -j | python3 -c '
import json, sys
found = [r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS")]
print(sorted(found)[-1] if found else "")')"
    type="com.apple.CoreSimulator.SimDeviceType.${name//[ ()]/-}"
    type="${type//--/-}"; type="${type%-}"
    [[ -n "$runtime" ]] && udid="$(xcrun simctl create "$name" "$type" "$runtime" 2>/dev/null || true)"
  fi
  if [[ -z "$udid" ]]; then
    echo "take-pictures.sh: no $name simulator (and none could be made); its App Store pictures are skipped." >&2
    return 1
  fi
  local result="$raw/store-$fallback_runtime_family.xcresult"
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 || true
  local code=0
  xcodebuild -project Pesto.xcodeproj -scheme PestoMobile -derivedDataPath .build/xcode-ios-app \
    -destination "platform=iOS Simulator,id=$udid" -only-testing:PestoMobileUITests/StoreScreenshotTests \
    -resultBundlePath "$result" test >"$raw/store-$fallback_runtime_family.log" 2>&1 || code=$?
  xcrun simctl status_bar "$udid" clear || true
  xcrun xcresulttool export attachments --path "$result" --output-path "$raw/store-$fallback_runtime_family" >/dev/null 2>&1 || true
  python3 - "$raw/store-$fallback_runtime_family" .build/app-store <<'PY'
import json, os, re, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
manifest = os.path.join(raw, "manifest.json")
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for att in test.get("attachments", []):
            name = re.sub(r"_0_[0-9A-F-]{36}(\.\w+)?$", "", att.get("suggestedHumanReadableName", ""))
            src = os.path.join(raw, att["exportedFileName"])
            if name.startswith("ios-store-") and src.endswith(".png"):
                shutil.copyfile(src, os.path.join(out, name + ".png"))
PY
  rm -rf "$raw/store-$fallback_runtime_family"
  return "$code"
}

rm -rf .build/app-store
mkdir -p .build/app-store
store_pictures "iPhone 17 Pro Max" iphone || status=$?
store_pictures "iPad Pro 13-inch (M5)" ipad || status=$?
echo "App Store pictures in .build/app-store"

stamp="commit $(git rev-parse HEAD)"
[[ -z "$(git status --porcelain --untracked-files=no -- Sources Tests Pesto.yml)" ]] || stamp="$stamp dirty"
echo "$stamp" > docs/images/SOURCE
echo "$stamp" > .build/marketing/SOURCE
echo "pictures taken from $stamp (logs in $raw)"
exit "$status"
