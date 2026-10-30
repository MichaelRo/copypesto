#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Prints how many seconds to ADD to this Mac's clock to get Apple's time (sntp), for writer.py and reader.swift:
#   scripts/sync-latency/clock-offset.sh
set -euo pipefail
out="$(sntp time.apple.com 2>&1 | grep -E '^[+-][0-9.]+ ' | head -1 || true)"
offset="$(awk '{print $1}' <<<"$out")"
[[ "$offset" =~ ^[+-]?[0-9.]+$ ]] || { echo "clock-offset: could not read an offset from: $out" >&2; exit 1; }
echo "$offset"
