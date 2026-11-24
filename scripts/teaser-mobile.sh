#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Captures iPhone and iPad frames (light and dark) for the website showcase video and exports them
# to copypesto-website/video/teaser/public/frames/mobile/{light,dark}/.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
website="${PESTO_WEBSITE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --website) website="$2"; shift 2 ;;
    *) echo "teaser-mobile.sh: unknown option $1" >&2; exit 2 ;;
  esac
done
if [ -z "$website" ]; then
  for candidate in ../copypesto-website "$HOME/Projects/copypesto-website"; do
    [ -d "$candidate/video/teaser" ] && website="$candidate" && break
  done
fi
[ -d "$website/video/teaser" ] || { echo "teaser-mobile.sh: website checkout not found. Pass --website DIR or set PESTO_WEBSITE." >&2; exit 2; }

find_sim() {
  local preferred="$1" fallback="$2"
  xcrun simctl list devices available -j | python3 -c '
import json, sys
preferred, fallback = sys.argv[1], sys.argv[2]
devices = [d for _, ds in sorted(json.load(sys.stdin)["devices"].items(), reverse=True) for d in ds if d.get("isAvailable", True)]
for name in (preferred, fallback):
    for d in devices:
        if d["name"] == name:
            print(d["udid"]); raise SystemExit
' "$preferred" "$fallback"
}

iphone_udid="$(find_sim "iPhone 17" "iPhone 18 Pro Max")"
ipad_udid="$(find_sim "iPad Air 11-inch (M4)" "iPad Pro 13-inch (M5)")"
[ -n "$iphone_udid" ] || { echo "teaser-mobile.sh: no iPhone simulator found" >&2; exit 1; }
[ -n "$ipad_udid" ] || { echo "teaser-mobile.sh: no iPad simulator found" >&2; exit 1; }

raw=".build/teaser-mobile/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$raw"

echo "building PestoMobile for testing..."
derived=".build/xcode-ios-teaser"
xcodebuild -project Pesto.xcodeproj -scheme PestoMobile -derivedDataPath "$derived" \
  -destination "generic/platform=iOS Simulator" \
  build-for-testing >"$raw/build.log" 2>&1

capture_device() {
  local udid="$1" test_name="$2" mode="$3" label="$4"
  local result="$raw/${label}-${mode}.xcresult"
  local exported="$raw/${label}-${mode}"
  local dest="$website/video/teaser/public/frames/mobile/$mode"
  local raw_mp4="$raw/${label}-${mode}-raw.mp4"
  mkdir -p "$dest"
  echo "capturing $label ($mode)..."
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 || true
  xcrun simctl ui "$udid" appearance "$mode" >/dev/null 2>&1 || true
  if [ "$mode" = dark ]; then export TEST_RUNNER_PESTO_TEASER_MODE=dark; else unset TEST_RUNNER_PESTO_TEASER_MODE; fi
  rm -rf "$result" "$exported" "$raw_mp4"
  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$raw_mp4" >/dev/null 2>&1 &
  local rec_pid=$!
  xcodebuild -project Pesto.xcodeproj -scheme PestoMobile -derivedDataPath "$derived" \
    -destination "platform=iOS Simulator,id=$udid" \
    -only-testing:"PestoMobileUITests/TeaserMobileFramesTests/$test_name" \
    -resultBundlePath "$result" test-without-building >"$raw/${label}-${mode}.log" 2>&1 || true
  kill -INT "$rec_pid" >/dev/null 2>&1 || true
  wait "$rec_pid" >/dev/null 2>&1 || true
  if [ -s "$raw_mp4" ]; then
    ffmpeg -v error -y -sseof -4.5 -i "$raw_mp4" -an -c:v libx264 -crf 20 -pix_fmt yuv420p -r 60 "$dest/mobile-${label}-clip.mp4" || true
  fi
  xcrun simctl status_bar "$udid" clear || true
  xcrun xcresulttool export attachments --path "$result" --output-path "$exported" >/dev/null 2>&1
  local dest="$website/video/teaser/public/frames/mobile/$mode"
  mkdir -p "$dest"
  python3 - "$exported" "$dest" <<'PY'
import json, os, re, shutil, sys
raw, out = sys.argv[1], sys.argv[2]
manifest = os.path.join(raw, "manifest.json")
count = 0
for test in json.load(open(manifest)):
    for att in test.get("attachments", []):
        name = re.sub(r"_0_[0-9A-F-]{36}(\.\w+)?$", "", att.get("suggestedHumanReadableName", ""))
        src = os.path.join(raw, att["exportedFileName"])
        if name.startswith("mobile-") and src.endswith(".png"):
            shutil.copyfile(src, os.path.join(out, name + ".png"))
            count += 1
print(f"exported {count} files to {out}")
PY
  rm -rf "$exported"
}

for mode in light dark; do
  capture_device "$iphone_udid" "test_onIPhone_teaserFrames" "$mode" "iphone"
  capture_device "$ipad_udid" "test_onIPad_teaserFrames" "$mode" "ipad"
done

echo "Mobile frames exported to $website/video/teaser/public/frames/mobile/{light,dark}/"
