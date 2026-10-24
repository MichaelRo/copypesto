#!/bin/bash
# SPDX-License-Identifier: MIT
# Joins the frames of each loop in .build/marketing/loops (loop-<scene>-<mode>-<nn>-<hold in ms>@2x.png, from
# `make marketing-loops`) into an animated AVIF at 1200 px wide, plus the still the page shows under Reduce Motion
# (the frame that says the most). Output: .build/marketing/loops/loop-<scene>-<mode>.avif and <scene>-<mode>-still@2x.png.
# The website repo takes them from there (scripts/marketing/copy-from-app.sh). Needs ffmpeg with libsvtav1.
set -euo pipefail
cd "$(dirname "$0")/.."

DIR=.build/marketing/loops
MAX_KB=${PESTO_LOOP_MAX_KB:-320}
command -v ffmpeg > /dev/null || { echo "ffmpeg is missing (brew install ffmpeg)" >&2; exit 1; }
encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null)
grep -q libsvtav1 <<< "$encoders" || { echo "this ffmpeg has no libsvtav1" >&2; exit 1; }
ls "$DIR"/loop-*@2x.png > /dev/null 2>&1 || { echo "no frames in $DIR; run make marketing-loops" >&2; exit 1; }

# The still for each scene: the frame the page should show when nothing moves.
still_frame() {
  case "$1" in
    find) echo 03 ;;
    secret) echo 01 ;;
    *) echo 00 ;;
  esac
}

for first in "$DIR"/loop-*-00-*@2x.png; do
  base=$(basename "$first")
  scene=$(echo "$base" | cut -d- -f2)
  mode=$(echo "$base" | cut -d- -f3)
  list=$(mktemp)
  last=""
  for frame in $(ls "$DIR"/loop-"$scene"-"$mode"-*@2x.png | sort); do
    hold=$(basename "$frame" | sed -E 's/.*-([0-9]+)@2x\.png/\1/')
    printf "file '%s'\nduration %s\n" "$PWD/$frame" "$(awk "BEGIN{print $hold/1000}")" >> "$list"
    last="$PWD/$frame"
  done
  # The concat demuxer ignores the last duration unless the last file is listed once more.
  printf "file '%s'\n" "$last" >> "$list"
  out="$DIR/loop-$scene-$mode.avif"
  ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" \
    -vf "scale=1200:-2:flags=lanczos,format=yuv420p" -c:v libsvtav1 -crf 38 -preset 4 -f avif "$out"
  rm -f "$list"
  cp "$DIR/loop-$scene-$mode-$(still_frame "$scene")"-*@2x.png "$DIR/$scene-$mode-still@2x.png"
  kb=$(( $(wc -c < "$out") / 1000 ))
  echo "$out  ${kb} KB"
  [ "$kb" -le "$MAX_KB" ] || { echo "$out is over $MAX_KB KB; raise -crf or drop a frame" >&2; exit 1; }
done
