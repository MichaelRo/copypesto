#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Inspects or captures Pesto's overlay alongside any active Touch ID / LocalAuthentication system prompt window
# (coreautha, LocalAuthenticationRemoteService, SecurityAgent) using CGWindowList + screencapture.
set -euo pipefail

OUTPUT=".build/touchid-prompt.png"
TIMEOUT=15
LIST_ONLY=0
WAIT_FOR_PROMPT=1

usage() {
  cat <<'EOF'
Usage: scripts/capture-touchid-prompt.sh [options]

Safe, read-only helper that inspects on-screen Pesto and Touch ID / LocalAuthentication
system windows (`coreautha`, `LocalAuthenticationRemoteService`, `SecurityAgent`) via
CoreGraphics and optionally captures their combined region with `screencapture`.

Options:
  --output <path>     Destination PNG path (default: .build/touchid-prompt.png)
  --timeout <secs>    Seconds to poll for Pesto + Touch ID windows (default: 15)
  --now               Capture immediately without polling
  --list, --dry-run   Read-only: list matching on-screen windows and exit without capturing
  -h, --help          Show this help text and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --list|--dry-run)
      LIST_ONLY=1
      shift
      ;;
    --now)
      WAIT_FOR_PROMPT=0
      shift
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "error: --output requires a path" >&2; exit 2; }
      OUTPUT="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { echo "error: --timeout requires a number" >&2; exit 2; }
      TIMEOUT="$2"
      shift 2
      ;;
    *)
      echo "error: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

inspect_windows() {
  /usr/bin/swift -e '
import CoreGraphics
import Foundation

let authOwners: Set<String> = [
    "coreautha",
    "LocalAuthenticationRemoteService",
    "SecurityAgent"
]

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("STATUS:NO_WINDOW_LIST")
    exit(0)
}

var pestoRect: CGRect?
var authRects: [(String, CGRect)] = []

for entry in list {
    guard let owner = entry[kCGWindowOwnerName as String] as? String,
          let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: boundsDict),
          rect.width > 1, rect.height > 1 else {
        continue
    }
    let layer = (entry[kCGWindowLayer as String] as? Int) ?? 0
    if owner == "Pesto", rect.width >= 200, rect.height >= 100, layer >= 0 {
        pestoRect = pestoRect.map { $0.union(rect) } ?? rect
    } else if authOwners.contains(owner), layer >= 0 {
        authRects.append((owner, rect))
    }
}

if let pestoRect {
    print("PESTO:\(Int(pestoRect.origin.x)),\(Int(pestoRect.origin.y)),\(Int(pestoRect.width)),\(Int(pestoRect.height))")
}
for (owner, rect) in authRects {
    print("AUTH:\(owner):\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))")
}

let combined = authRects.reduce(pestoRect) { partial, item in
    partial.map { $0.union(item.1) } ?? item.1
}
if let combined {
    print("UNION:\(Int(combined.origin.x)),\(Int(combined.origin.y)),\(Int(combined.width)),\(Int(combined.height))")
} else {
    print("STATUS:NO_MATCHING_WINDOWS")
}
'
}

if [[ "$LIST_ONLY" -eq 1 ]]; then
  echo "Inspecting on-screen Pesto and Touch ID windows (read-only)..."
  inspect_windows
  exit 0
fi

union_rect=""
deadline=$(( $(date +%s) + TIMEOUT ))
while true; do
  snapshot="$(inspect_windows)"
  has_pesto=0
  has_auth=0
  if grep -q '^PESTO:' <<<"$snapshot"; then has_pesto=1; fi
  if grep -q '^AUTH:' <<<"$snapshot"; then has_auth=1; fi
  union_rect="$(awk -F: '/^UNION:/{print $2; exit}' <<<"$snapshot")"

  if [[ "$WAIT_FOR_PROMPT" -eq 0 ]]; then
    break
  fi
  if [[ "$has_pesto" -eq 1 && "$has_auth" -eq 1 ]]; then
    break
  fi
  if [[ "$(date +%s)" -ge "$deadline" ]]; then
    break
  fi
  sleep 0.25
done

if [[ -z "$union_rect" ]]; then
  echo "error: no visible Pesto overlay or Touch ID prompt window found on screen" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
/usr/sbin/screencapture -x -R"$union_rect" "$OUTPUT"
echo "Captured Touch ID prompt region ($union_rect) to $OUTPUT"
