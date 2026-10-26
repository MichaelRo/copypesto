#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copies the documentation screenshots out of the newest verify run (`scripts/verify.sh`, which drives the real app
# with seeded demo data) into docs/images. Re-run after a design change, then commit the result. Pass a run folder
# (.build/ui-screenshots/<stamp>) to use one other than the newest by name.
set -euo pipefail
cd "$(dirname "$0")/.."

run="${1:-$(ls -d .build/ui-screenshots/[0-9]*/ 2>/dev/null | sort | tail -1)}"
[[ -n "$run" ]] || { echo "no screenshots: run scripts/verify.sh first" >&2; exit 1; }
out=docs/images
mkdir -p "$out"

copy() {
  local source; source="$(find "$run" -name "$1" | head -1)"
  [[ -n "$source" ]] || { echo "missing $1 in $run" >&2; exit 1; }
  cp "$source" "$out/$2"
}

copy showcase-dark.png shelf-dark.png
copy showcase-light.png shelf-light.png   # the Overview's pair
copy showcase-search.png search.png
copy showcase-ask.png ask-pesto.png
copy showcase-collections.png collections.png
copy showcase-settings-collections.png settings-collections.png
copy settings-Snippets.png settings-snippets.png
copy settings-shortcuts.png settings-shortcuts.png
copy about.png about.png
copy showcase-sensitive.png sensitive-card.png
copy history-locked.png history-locked.png
copy onboarding-shelf-step.png onboarding-welcome.png
copy onboarding-accessibility-denied.png onboarding.png
copy onboarding-ready.png onboarding-ready.png
copy shelf-basil-light.png theme-basil-light.png
copy shelf-basil-dark.png theme-basil-dark.png
copy shelf-parmesan-light.png theme-parmesan-light.png
copy shelf-parmesan-dark.png theme-parmesan-dark.png
copy shelf-pineNut-light.png theme-pine-nut-light.png
copy shelf-pineNut-dark.png theme-pine-nut-dark.png
copy shelf-mortar-light.png theme-mortar-light.png
copy shelf-mortar-dark.png theme-mortar-dark.png
copy settings-Data.png settings-data.png
# General, Appearance and Privacy come as a light and a dark picture; the guide names the light one and the website
# swaps in the dark one for a reader whose page is dark.
for pane in general appearance privacy; do
  for mode in light dark; do
    copy "settingspane-$pane-$mode.png" "settings-$pane-$mode.png"
  done
done
for image in "$out"/*.png; do
  width="$(sips -g pixelWidth "$image" | awk '/pixelWidth/{print $2}')"
  [[ "$width" -le 2000 ]] || sips --resampleWidth 2000 "$image" >/dev/null
done
echo "exported to $out from $run"
