#!/bin/bash
# SPDX-License-Identifier: MIT
# Copies the website screenshots from the newest UI-test result into .build/marketing/, named as the test
# attached them (hero-light@2x.png, 01-shelf-dark@2x.png, ...). Run by `make marketing-images`; never resamples.
# The website repo takes them from there: scripts/marketing/copy-from-app.sh in that repo.
set -euo pipefail
cd "$(dirname "$0")/.."

RESULT=$(ls -td .build/xcode/Logs/Test/*.xcresult 2>/dev/null | head -1 || true)
[ -n "$RESULT" ] || { echo "no UI-test result in .build/xcode/Logs/Test; run make marketing-images" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} \
  xcrun xcresulttool export attachments --path "$RESULT" --output-path "$WORK" > /dev/null

OUT=.build/marketing
mkdir -p "$OUT"
python3 - "$WORK" "$OUT" <<'PY'
import json, shutil, subprocess, sys
work, out = sys.argv[1], sys.argv[2]
count = 0
for test in json.load(open(f"{work}/manifest.json")):
    for item in test["attachments"]:
        name = item["suggestedHumanReadableName"].split("_0_")[0]
        if "@2x" not in name:
            continue
        target = f"{out}/{name}.png"
        shutil.copy(f"{work}/{item['exportedFileName']}", target)
        size = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", target],
                              capture_output=True, text=True).stdout.split()
        print(f"{target}  {size[-3]} x {size[-1]}")
        count += 1
print(f"{count} images in {out}")
PY
