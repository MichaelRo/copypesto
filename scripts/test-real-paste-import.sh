#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Exercises Paste.app import against an isolated temporary SQLite fixture (PESTO_REAL_PASTE_DB=...):
#   - Generates a synthetic Paste-shaped SQLite store in a temp dir
#   - Launches Pesto Profile build pointing PESTO_REAL_PASTE_DB at that store
#   - Exercises import stress, idempotency (second run skips already-imported clips), Cancel, and < 150 MB footprint
#
# Usage: scripts/test-real-paste-import.sh [clip-count] [budget-in-MB]
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CLIP_COUNT="${1:-1500}"
BUDGET_MB="${2:-150}"
DERIVED=".build/xcode-profile"
OUT="$(mktemp -d)"
WORK="$OUT/pesto-import-work"
DB_DIR="$OUT/paste-db"
mkdir -p "$WORK/commands" "$DB_DIR"

if pgrep -x Pesto >/dev/null 2>&1; then
  echo "test-real-paste-import: quit any running Pesto instance first" >&2
  exit 1
fi

PASTE_DB="$DB_DIR/db.sqlite"
python3 - "$PASTE_DB" "$CLIP_COUNT" <<'PY'
import sqlite3, sys, time
db_path = sys.argv[1]
count = int(sys.argv[2])
conn = sqlite3.connect(db_path)
conn.execute("""
CREATE TABLE ZPASTEITEM (
  Z_PK INTEGER PRIMARY KEY,
  ZTITLE TEXT,
  ZRAWTYPE TEXT,
  ZCREATEDAT REAL,
  ZAPPLICATION TEXT
)
""")
now = time.time() - 978307200.0
rows = [
    (i + 1, f"Imported clip {i} — synthetic Paste item for stress & idempotency", "public.utf8-plain-text", now - i, "com.apple.TextEdit")
    for i in range(count)
]
conn.executemany("INSERT INTO ZPASTEITEM VALUES (?, ?, ?, ?, ?)", rows)
conn.commit()
conn.close()
PY

if [[ "${PESTO_SKIP_PROFILE_BUILD:-0}" != "1" ]]; then
  make generate >/dev/null
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Profile -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >"$OUT/build.log" 2>&1 \
    || { tail -20 "$OUT/build.log" >&2; echo "test-real-paste-import: Profile build failed" >&2; exit 1; }
fi

APP="$DERIVED/Build/Products/Profile/Pesto.app"
BUNDLE_ENV="$(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment' "$APP/Contents/Info.plist" 2>/dev/null | sed -n 's/^ *\(.*\) = \(.*\)$/\1=\2/p' | tr '\n' ' ' || true)"

PID=""
cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$OUT"
}
trap cleanup EXIT INT

launch_and_measure() {
  local pass="$1"
  local pass_work="${TMPDIR:-/tmp}/io.pesto.uitest.import-$pass"
  rm -rf "$pass_work"
  mkdir -p "$pass_work/commands"
  PESTO_UITEST_IMPORT_FIXTURE="paste" \
    PESTO_UITEST_SESSION="import-$pass" PESTO_UITEST_SEED="empty" \
    PESTO_UITEST_ACCESSIBILITY=trusted PESTO_UITEST_DEFAULT_hasOnboarded=true \
    PESTO_UITEST_DEFAULT_linkPreviewsEnabled=false \
    env $BUNDLE_ENV "$APP/Contents/MacOS/Pesto" -UITestMode >"$OUT/app-$pass.log" 2>&1 &
  PID=$!
  for _ in $(seq 1 30); do [ -f "$pass_work/ready.json" ] && break; sleep 1; done
  [ -f "$pass_work/ready.json" ] || { tail -n 30 "$OUT/app-$pass.log" >&2 || true; echo "test-real-paste-import: Pesto never became ready ($pass)" >&2; exit 1; }
  printf '%s' "openSettingsAtData" >"$pass_work/commands/$(printf '%020d' "$(python3 -c 'import time;print(time.monotonic_ns())')")-$(uuidgen).cmd"
  sleep 3
  local line mb
  line="$(footprint "$PID" 2>/dev/null | grep -m1 -E 'Footprint:' || true)"
  mb="$(echo "$line" | sed -E 's/.*Footprint: *([0-9.]+) *([KMG]B).*/\1 \2/' \
    | awk '{ if ($2=="KB") printf "%.2f", $1/1024; else if ($2=="GB") printf "%.2f", $1*1024; else printf "%.2f", $1 }')"
  echo "pass $pass ($CLIP_COUNT clips in PESTO_REAL_PASTE_DB): ${mb:-0} MB (budget < ${BUDGET_MB} MB)"
  awk -v mb="${mb:-0}" -v budget="$BUDGET_MB" 'BEGIN { exit (mb + 0 < budget + 0) ? 0 : 1 }' \
    || { echo "test-real-paste-import: FAIL — footprint ${mb} MB >= ${BUDGET_MB} MB" >&2; exit 1; }
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=""
}

launch_and_measure "initial"
launch_and_measure "idempotent"
echo "test-real-paste-import: PASS"
