#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# After a release is live (the appcast offers it), runs the Homebrew tap's bump workflow at once instead of waiting for its
# six-hourly poll, and prints the pull request it opens. The tap checks the disk image (hash, size, signature,
# notarization) before it proposes anything; merge that pull request, then `brew upgrade --cask --greedy pesto` to try it.
#   scripts/bump-cask.sh [version]     (default: the newest version in the live appcast)
set -euo pipefail
tap="${PESTO_TAP:-MichaelRo/homebrew-copypesto}"
live="$(curl -fsS --max-time 30 https://copypesto.net/appcast.xml \
  | grep -o 'shortVersionString>[0-9.]*' | sed 's/.*>//' | sort -V | tail -1)"
version="${1:-$live}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bump-cask: no version (appcast said '$live')" >&2; exit 1; }
[[ "$live" == "$version" ]] || { echo "bump-cask: the live appcast offers $live, not $version. Deploy the site first." >&2; exit 1; }
current="$(gh api "repos/$tap/contents/Casks/pesto.rb" --jq .content | base64 -d | sed -n 's/^  version "\(.*\)"$/\1/p')"
if [[ "$current" == "$version" ]]; then echo "The cask is already at $version."; exit 0; fi
gh workflow run bump --repo "$tap" >/dev/null
echo "Started the bump workflow for $version (the cask is at $current). Waiting for its pull request..."
for _ in $(seq 1 40); do
  url="$(gh pr list --repo "$tap" --state open --search "pesto $version in:title" --json url --jq '.[0].url // empty')"
  [[ -n "$url" ]] && { echo "Merge this after its checks pass: $url"; exit 0; }
  sleep 15
done
echo "No pull request after 10 minutes: look at https://github.com/$tap/actions" >&2
exit 1
