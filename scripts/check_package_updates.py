#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compare the SwiftPM pins in Pesto.yml with each repository's latest GitHub release and known advisories.

Read-only. The only network use is `gh api` against api.github.com. With PESTO_PACKAGES_FIXTURE set to a folder, it
reads `<owner>__<repo>.release.json` and `<owner>__<repo>.advisories.json` from there instead (the tests do this).
Always exits 0; a package that is behind or vulnerable gets a loud line.
"""
import json
import os
import re
import subprocess
import sys


def parse_pins(text):
    """Return [(owner/repo, version, revision)] for every package under `packages:` that has a github url."""
    pins = []
    in_packages = False
    current = None
    for line in text.splitlines():
        if re.match(r"^packages:\s*$", line):
            in_packages = True
            continue
        if in_packages and re.match(r"^\S", line):
            in_packages = False
        if not in_packages:
            continue
        url = re.match(r"^\s+url:\s*https://github\.com/([^/\s]+/[^/\s]+?)(?:\.git)?\s*$", line)
        if url:
            current = {"repo": url.group(1), "version": None, "revision": None}
            pins.append(current)
            continue
        if current is None:
            continue
        comment = re.match(r"^\s+#\s*v?(\d+(?:\.\d+)*(?:[-+][0-9A-Za-z.]+)?)\b", line)
        if comment and current["version"] is None:
            current["version"] = comment.group(1)
        revision = re.match(r"^\s+revision:\s*([0-9a-f]{40})\s*$", line)
        if revision:
            current["revision"] = revision.group(1)
        version = re.match(r"^\s+(?:exactVersion|version|from):\s*\"?v?(\d+(?:\.\d+)*)\"?\s*$", line)
        if version and current["version"] is None:
            current["version"] = version.group(1)
    return [(p["repo"], p["version"], p["revision"]) for p in pins]


def version_key(text):
    core = re.split(r"[-+]", text, maxsplit=1)[0]
    numbers = tuple(int(part) for part in core.split(".") if part.isdigit())
    prerelease = 0 if re.search(r"[-]", text) else 1
    return numbers + (0,) * (4 - len(numbers)), prerelease


def compare(a, b):
    ka, kb = version_key(a), version_key(b)
    return (ka > kb) - (ka < kb)


def in_range(version, expression):
    """True when `version` satisfies a GitHub range such as '>= 2.2.0, < 2.9.5' or '<= 2.9.1'."""
    if not expression:
        return False
    for clause in expression.split(","):
        match = re.match(r"^\s*(<=|>=|<|>|=)?\s*v?(\S+)\s*$", clause)
        if not match:
            return False
        operator, bound = match.group(1) or "=", match.group(2)
        order = compare(version, bound)
        holds = {"<=": order <= 0, ">=": order >= 0, "<": order < 0, ">": order > 0, "=": order == 0}[operator]
        if not holds:
            return False
    return True


def names_repo(package_name, repo):
    name = package_name.lower().removeprefix("github.com/").removesuffix(".git")
    wanted = repo.lower()
    return name == wanted or name == wanted.split("/")[1]


def vulnerable_advisories(advisories, repo, version):
    found = {}
    for advisory in advisories:
        for entry in advisory.get("vulnerabilities") or []:
            package = (entry.get("package") or {}).get("name", "")
            if names_repo(package, repo) and in_range(version, entry.get("vulnerable_version_range")):
                patched = entry.get("first_patched_version") or entry.get("patched_versions") or "none listed"
                if isinstance(patched, dict):
                    patched = patched.get("identifier", "none listed")
                key = advisory.get("ghsa_id") or advisory.get("summary")
                found[key] = (advisory.get("summary", "advisory"), patched)
    return sorted(found.items())


def gh(path):
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def fetch(repo):
    fixture = os.environ.get("PESTO_PACKAGES_FIXTURE")
    if fixture:
        stem = os.path.join(fixture, repo.replace("/", "__"))
        with open(stem + ".release.json", encoding="utf-8") as handle:
            release = json.load(handle)
        with open(stem + ".advisories.json", encoding="utf-8") as handle:
            advisories = json.load(handle)
        return release, advisories
    release = gh(f"repos/{repo}/releases/latest")
    advisories = []
    name = repo.split("/")[1]
    for affects in (f"github.com/{repo}", repo, name):
        advisories += gh(f"/advisories?ecosystem=swift&per_page=100&affects={affects}") or []
    advisories += gh(f"repos/{repo}/security-advisories") or []
    return release, advisories


def main(argv):
    path = argv[1] if len(argv) > 1 else "Pesto.yml"
    with open(path, encoding="utf-8") as handle:
        pins = parse_pins(handle.read())
    if not pins:
        print("check-packages: found no GitHub package pins in", path)
        return 0
    rows = []
    alerts = []
    for repo, pinned, _revision in pins:
        release, advisories = fetch(repo)
        latest = ((release or {}).get("tag_name") or "unknown").removeprefix("v")
        if pinned is None:
            rows.append((repo, "unknown", latest, "CHECK BY HAND"))
            alerts.append(f"{repo}: the pinned version could not be read from {path}")
            continue
        behind = latest != "unknown" and compare(pinned, latest) < 0
        hits = vulnerable_advisories(advisories, repo, pinned)
        rows.append((repo, pinned, latest, "BEHIND" if behind else "current"))
        if behind:
            alerts.append(f"{repo} is behind: pinned {pinned}, latest {latest}")
        for key, (summary, patched) in hits:
            alerts.append(f"{repo} {pinned} is VULNERABLE: {key} {summary} (patched in {patched})")
        if latest != "unknown":
            for key, (summary, _patched) in vulnerable_advisories(advisories, repo, latest):
                alerts.append(f"{repo} latest {latest} also has a known advisory: {key} {summary}")
    width = max(len(row[0]) for row in rows)
    print(f"{'package'.ljust(width)}  {'pinned':<10} {'latest':<10} status")
    for repo, pinned, latest, status in rows:
        print(f"{repo.ljust(width)}  {pinned:<10} {latest:<10} {status}")
    for alert in alerts:
        print(f"!!! check-packages: {alert}")
    if not alerts:
        print("check-packages: every pin is the latest release and no advisory covers it")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
