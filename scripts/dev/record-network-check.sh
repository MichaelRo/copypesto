#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Records a dated network activity snapshot of a running Pesto process for the Privacy page (H-04).
# Uses lsof and nettop to inspect open sockets and connections while Pesto runs.
#
# Usage: scripts/dev/record-network-check.sh [--assert-zero] [--duration <seconds> | <seconds>]
set -euo pipefail

DURATION=""
ASSERT_ZERO=0
while [ $# -gt 0 ]; do
  case "$1" in
    --assert-zero)
      ASSERT_ZERO=1
      shift
      ;;
    --duration)
      DURATION="${2:-15}"
      shift 2
      ;;
    --duration=*)
      DURATION="${1#*=}"
      shift
      ;;
    *)
      DURATION="$1"
      shift
      ;;
  esac
done

if [ -z "$DURATION" ]; then
  if [ "$ASSERT_ZERO" = "1" ]; then
    DURATION=30
  else
    DURATION=15
  fi
fi

PID=$(pgrep -x Pesto | head -1 || true)

if [ -z "$PID" ]; then
  echo "error: Pesto is not running. Start Pesto ('make run' or open Pesto.app) and re-run." >&2
  exit 1
fi

MACOS_VER=$(sw_vers -productVersion)
MACOS_BUILD=$(sw_vers -buildVersion)
DATE_ISO=$(date +%Y-%m-%d)
OUT_FILE=".build/network-check-${DATE_ISO}.md"
mkdir -p .build

echo "=== Pesto Network Check ($DATE_ISO, macOS $MACOS_VER) ==="
echo "Monitoring Pesto (PID $PID) for ${DURATION}s..."
echo "While this runs, copy some text, code, or an image in another app and open the Pesto shelf."

OPEN_BEFORE=$(lsof -n -P -i -a -p "$PID" 2>/dev/null || true)
NETTOP_OUT=$(nettop -P -L 3 -s "$(( (DURATION + 2) / 3 ))" -p "$PID" 2>/dev/null || true)
OPEN_AFTER=$(lsof -n -P -i -a -p "$PID" 2>/dev/null || true)

cat > "$OUT_FILE" <<REPORT
# Pesto Dated Network Check — $DATE_ISO

- **Date**: $DATE_ISO
- **macOS**: $MACOS_VER ($MACOS_BUILD)
- **Process**: \`Pesto\` (PID $PID)
- **Link Previews (\`linkPreviewsEnabled\`)**: $(defaults read net.copypesto.pesto linkPreviewsEnabled 2>/dev/null || echo "false (default)")

## Open network sockets before check (\`lsof -n -P -i -a -p $PID\`)
\`\`\`
${OPEN_BEFORE:-"(zero open network sockets)"}
\`\`\`

## \`nettop\` process summary over ${DURATION}s
\`\`\`
${NETTOP_OUT:-"(zero network traffic rows)"}
\`\`\`

## Open network sockets after check (\`lsof -n -P -i -a -p $PID\`)
\`\`\`
${OPEN_AFTER:-"(zero open network sockets)"}
\`\`\`
REPORT

echo ""
echo "✓ Network check saved to $OUT_FILE"
cat "$OUT_FILE"

if [ "$ASSERT_ZERO" = "1" ]; then
  BEFORE_SOCKETS=$(printf '%s\n' "$OPEN_BEFORE" | grep -v '^COMMAND' | grep -v '^$' || true)
  AFTER_SOCKETS=$(printf '%s\n' "$OPEN_AFTER" | grep -v '^COMMAND' | grep -v '^$' || true)
  if [ -n "$BEFORE_SOCKETS" ] || [ -n "$AFTER_SOCKETS" ]; then
    echo "FAIL: --assert-zero detected open network sockets for Pesto (PID $PID)" >&2
    exit 1
  fi
  NONZERO_BYTES=$(printf '%s\n' "$NETTOP_OUT" | awk -F, '
    NR > 1 && $1 != "" && $1 !~ /^time/ {
      for (i = 2; i <= NF; i++) {
        gsub(/[^0-9]/, "", $i)
        if ($i != "" && ($i + 0) > 0) { print; exit 0 }
      }
    }
  ' || true)
  if [ -n "$NONZERO_BYTES" ]; then
    echo "FAIL: --assert-zero detected non-zero nettop byte transfer: $NONZERO_BYTES" >&2
    exit 1
  fi
  echo "✓ --assert-zero passed: 0 sockets, 0 bytes transferred over ${DURATION}s"
fi
