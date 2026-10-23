#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Records a dated network activity snapshot of a running Pesto process for the Privacy page (H-04).
# Uses lsof and nettop to inspect open sockets and connections while Pesto runs.
#
# Usage: scripts/dev/record-network-check.sh [--duration <seconds> | <seconds>]
set -euo pipefail

DURATION=15
while [ $# -gt 0 ]; do
  case "$1" in
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
- **Link Previews (\`fetchLinkPreviews\`)**: $(defaults read net.copypesto.pesto fetchLinkPreviews 2>/dev/null || echo "false (default)")

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
