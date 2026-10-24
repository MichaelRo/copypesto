#!/bin/bash
# SPDX-License-Identifier: MIT
# Joins the frames of each scene in .build/marketing/loops (loop-<scene>-<mode>-<nn>-<hold in ms>@2x.png, from
# `make marketing-loops`) into the moving pictures for the places the website does not use them:
#   .build/marketing/video/pesto-<scene>-<mode>.mp4   H.264, no audio: launch posts, social, the press kit
#   .build/marketing/video/pesto-<scene>-<mode>.webm   VP9, where the place takes it
#   .build/marketing/video/pesto-<scene>-<mode>.gif    for the README, the Sponsors page and directories that play no video
# The website plays the same frames by scroll (copy-from-app.sh there), so nothing on the site autoplays. Never use these on
# the site: an endless autoplay needs a pause control (WCAG 2.2.2), which needs script, and the CSP has no media-src.
# Needs ffmpeg with libx264 and libvpx-vp9; gifski gives the GIF without banding (brew install ffmpeg gifski).
set -euo pipefail
cd "$(dirname "$0")/.."

DIR=.build/marketing/loops
OUT=.build/marketing/video
GIF_MAX_KB=${PESTO_GIF_MAX_KB:-3000}
command -v ffmpeg > /dev/null || { echo "ffmpeg is missing (brew install ffmpeg gifski)" >&2; exit 1; }
encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null)
for encoder in libx264 libvpx-vp9; do
  grep -q "$encoder" <<< "$encoders" || { echo "this ffmpeg has no $encoder" >&2; exit 1; }
done
ls "$DIR"/loop-*@2x.png > /dev/null 2>&1 || { echo "no frames in $DIR; run make marketing-loops" >&2; exit 1; }
mkdir -p "$OUT"

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
  name="$OUT/pesto-$scene-$mode"
  # Even dimensions (H.264 needs them), 30 fps for video, no audio, streams from the first byte.
  ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" -an \
    -vf "scale=1280:-2:flags=lanczos,fps=30" -c:v libx264 -crf 22 -preset slow -pix_fmt yuv420p -movflags +faststart "$name.mp4"
  ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" -an \
    -vf "scale=1280:-2:flags=lanczos,fps=30" -c:v libvpx-vp9 -crf 34 -b:v 0 "$name.webm"
  if command -v gifski > /dev/null; then
    frames=$(mktemp -d)
    ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" -vf "scale=1000:-2:flags=lanczos,fps=20" "$frames/f%04d.png"
    gifski --fps 20 --quality 90 -o "$name.gif" "$frames"/f*.png
    rm -rf "$frames"
  else
    # Without gifski: ffmpeg's own palette, which bands the shelf's glass gradients a little.
    ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" \
      -vf "scale=1000:-2:flags=lanczos,fps=20,split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a" "$name.gif"
    echo "note: gifski is missing, so $name.gif uses ffmpeg's palette" >&2
  fi
  rm -f "$list"
  for file in "$name.mp4" "$name.webm" "$name.gif"; do echo "$file  $(( $(wc -c < "$file") / 1000 )) KB"; done
  [ $(( $(wc -c < "$name.gif") / 1000 )) -le "$GIF_MAX_KB" ] || echo "warning: $name.gif is over $GIF_MAX_KB KB; use fewer frames or a narrower picture" >&2
done
echo "Check each file's size and its loop point before it goes anywhere (docs/motion.md in the website repo)."
