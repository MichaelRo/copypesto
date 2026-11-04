#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Retakes the website film's frames from this build (the shelf on the plain backdrop, light and dark), draws the film's
# pictures with the app's own drawing code, imports both into the website checkout and, unless --frames-only, renders,
# mixes and finishes both films there. Run by `make teaser` and `make teaser-frames`; docs/teaser.md is the guide.
#   scripts/teaser.sh [--website DIR] [--music FILE] [--frames-only]
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
website="${PESTO_WEBSITE:-}"
music="${PESTO_TEASER_MUSIC:-}"
frames_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --website) website="$2"; shift 2 ;;
    --music) music="$2"; shift 2 ;;
    --frames-only) frames_only=1; shift ;;
    *) echo "teaser.sh: unknown option $1" >&2; exit 2 ;;
  esac
done
if [ -z "$website" ]; then
  for candidate in ../copypesto-website "$HOME/Projects/copypesto-website"; do
    [ -d "$candidate/video/teaser" ] && website="$candidate" && break
  done
fi
[ -d "$website/video/teaser" ] || { echo "teaser.sh: the website checkout is not found. Pass --website DIR or set PESTO_WEBSITE." >&2; exit 2; }
if pgrep -x Pesto >/dev/null; then
  echo "teaser.sh: Pesto is running. Quit it and run this again." >&2
  exit 2
fi
if [ "$frames_only" = 0 ] && [ -z "$music" ]; then
  echo "teaser.sh: the film needs the music track (--music FILE or PESTO_TEASER_MUSIC), or use --frames-only." >&2
  exit 2
fi

raw=".build/teaser/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$raw"
for mode in light dark; do
  echo "taking the $mode frames..."
  result="$raw/$mode.xcresult"
  if [ "$mode" = dark ]; then export TEST_RUNNER_PESTO_TEASER_MODE=dark; else unset TEST_RUNNER_PESTO_TEASER_MODE; fi
  xcodebuild -project Pesto.xcodeproj -scheme Pesto -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath .build/xcode \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    -only-testing:PestoUITests/TeaserFramesTests -resultBundlePath "$result" test >"$raw/$mode.log" 2>&1 \
    || { echo "teaser.sh: the $mode frames failed, see $raw/$mode.log" >&2; exit 1; }
  rm -rf "$website/video/teaser/public/frames/$mode"
  python3 "$website/video/teaser/scripts/import_frames.py" "$result" "$mode"
done

echo "copying the menu bar icons..."
cp Sources/Resources/Assets.xcassets/MenuBarIcon.imageset/menubar@2x.png "$website/video/teaser/public/brand/menubar.png"
cp Sources/Resources/Assets.xcassets/MenuBarIconHidden.imageset/MenuBarIconHidden@2x.png "$website/video/teaser/public/brand/menubar-hidden.png"

echo "drawing the film's pictures..."
"$website/video/teaser/scripts/render_art.sh" "$PWD"

commit="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- Sources Tests || echo '+uncommitted')"
printf '%s\n' "$commit" >"$website/video/teaser/FRAMES-SOURCE"
echo "frames and pictures are in $website/video/teaser (app commit $commit)."

if [ "$frames_only" = 1 ]; then
  echo "Next: (cd $website/video/teaser && npm run film -- --music <track>) renders the films."
  exit 0
fi
(cd "$website/video/teaser" && ./scripts/make_film.sh --music "$music")
echo "Done. Look at both films, then run the website's build and tests, and commit the files it changed."
