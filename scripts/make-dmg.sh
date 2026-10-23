#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds the installer disk image: Pesto.app next to an Applications shortcut, over a background that says what to do.
#
#   scripts/make-dmg.sh path/to/Pesto.app path/to/Pesto-1.0.0.dmg
#
# Laying out the window needs Finder (it writes the icon positions into the volume), so run it in a logged-in session.
set -euo pipefail
APP=${1:?path to Pesto.app}
OUT=${2:?output .dmg path}
HERE="$(cd "$(dirname "$0")" && pwd)"
VOLUME=Pesto

WORK=$(mktemp -d)
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Pesto.app"
ln -s /Applications "$STAGE/Applications"
swift "$HERE/make-dmg-background.swift" "$STAGE/.background/background.png"

RW="$WORK/rw.dmg"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" > /dev/null
hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true
hdiutil attach "$RW" -readwrite -noverify -noautoopen > /dev/null

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set theOptions to the icon view options of container window
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 128
    set background picture of theOptions to file ".background:background.png"
    set position of item "Pesto.app" of container window to {170, 190}
    set position of item "Applications" of container window to {490, 190}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# Finder writes the layout into .DS_Store a moment after the window closes. An image detached before that opens as a
# plain window, so wait for the file and stop if it never appears.
for _ in $(seq 1 40); do
  [ -s "/Volumes/$VOLUME/.DS_Store" ] && break
  sleep 0.5
done
[ -s "/Volumes/$VOLUME/.DS_Store" ] || { echo "Finder did not save the window layout (.DS_Store is missing); run this in a logged-in session" >&2; exit 1; }

sync
hdiutil detach "/Volumes/$VOLUME" -quiet
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" > /dev/null
echo "$OUT"
