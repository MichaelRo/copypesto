#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# A reminder, never a failure: lists changes since the film's frames were last taken that show up in the website film.
# Called by .githooks/pre-push. It needs the website checkout (PESTO_WEBSITE, ../copypesto-website or ~/Projects/copypesto-website).
set -u
cd "$(dirname "$0")/.."
website="${PESTO_WEBSITE:-}"
if [ -z "$website" ]; then
  for candidate in ../copypesto-website "$HOME/Projects/copypesto-website"; do
    [ -f "$candidate/video/teaser/FRAMES-SOURCE" ] && website="$candidate" && break
  done
fi
[ -f "$website/video/teaser/FRAMES-SOURCE" ] || exit 0
since="$(sed 's/+uncommitted//' "$website/video/teaser/FRAMES-SOURCE" | head -1)"
git cat-file -e "$since^{commit}" 2>/dev/null || exit 0
changed="$(git diff --name-only "$since"..HEAD -- Sources/Features/Grid Sources/Features/Overlay Sources/Shared Sources/Core/Seeding/LunchRushSeed.swift \
  Sources/Core/Runtime/ShowcaseArt Tests/PestoUITests/TeaserFramesTests.swift | head -12)"
[ -n "$changed" ] || exit 0
printf '\033[33m%s\033[0m\n' "[pre-push] These files show up in the website film (frames taken at $since):"
printf '  %s\n' $changed
printf '\033[33m%s\033[0m\n' "[pre-push] If the shelf, a card or the glass looks different, run 'make teaser' (docs/teaser.md)."
exit 0
