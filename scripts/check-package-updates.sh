#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Compares the SwiftPM pins in Pesto.yml with each repository's latest release and known advisories (read-only; only
# api.github.com through `gh`). Dependabot cannot see Pesto.yml. Always exits 0: read the lines that start with "!!!".
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${PESTO_PACKAGES_FIXTURE:-}" ]] && ! command -v gh >/dev/null; then
    echo "!!! check-packages: gh is not installed"
    exit 0
fi
/usr/bin/env python3 -I "$root/scripts/check_package_updates.py" "${1:-$root/Pesto.yml}" || echo "!!! check-packages: the check itself failed"
exit 0
