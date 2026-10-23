#!/bin/bash
# SPDX-License-Identifier: MIT
# Copies the two pictures `make capture-real` took (the lock screen with the real Touch ID view, Ask answered by the
# on-device model) out of the newest UI-test result into docs/images, replacing the stub-made ones.
set -euo pipefail
cd "$(dirname "$0")/.."

RESULT=$(ls -td .build/xcode/Logs/Test/*.xcresult 2>/dev/null | head -1 || true)
[ -n "$RESULT" ] || { echo "no UI-test result in .build/xcode/Logs/Test; run make capture-real" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} \
  xcrun xcresulttool export attachments --path "$RESULT" --output-path "$WORK" > /dev/null

python3 - "$WORK" docs/images <<'PY'
import json, shutil, sys
work, out = sys.argv[1], sys.argv[2]
wanted = {"real-history-locked": "history-locked.png", "real-ask": "ask-pesto.png"}
found = set()
for test in json.load(open(f"{work}/manifest.json")):
    for item in test["attachments"]:
        name = item["suggestedHumanReadableName"].split("_0_")[0]
        if name in wanted:
            shutil.copy(f"{work}/{item['exportedFileName']}", f"{out}/{wanted[name]}")
            found.add(name)
            print(f"{out}/{wanted[name]}")
missing = set(wanted) - found
if missing:
    sys.exit(f"not taken (skipped or failed): {', '.join(sorted(missing))}")
PY
for image in docs/images/history-locked.png docs/images/ask-pesto.png; do
  width="$(sips -g pixelWidth "$image" | awk '/pixelWidth/{print $2}')"
  [[ "$width" -le 2000 ]] || sips --resampleWidth 2000 "$image" >/dev/null
done
echo "Look at both pictures before committing them: nothing but Pesto may be in them."
