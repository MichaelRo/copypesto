#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""A git merge driver for String Catalogs (`*.xcstrings`), entry by entry.

Every pull request adds strings to the one catalog, so two branches almost always "conflict" there although they
touched different keys. This merges the three versions per key: a key one side added or changed is taken from that side,
a key both sides set to the same value is kept once, and a key both changed differently is a real conflict, which the
driver reports by leaving our version in place and exiting 1, so git marks the file conflicted.

Registered by `make setup-merge-drivers` (see .gitattributes and docs/development.md, "Merging"):
    git config merge.xcstrings.driver "python3 scripts/merge-xcstrings.py %O %A %B"
Arguments: the common ancestor, ours (rewritten in place with the result), theirs.
"""
import json
import sys


def load(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    return json.loads(text) if text.strip() else {"sourceLanguage": "en", "strings": {}, "version": "1.0"}


def dump(document, path):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(document, ensure_ascii=False, indent=2, separators=(",", ": ")) + "\n")


def merge(base, ours, theirs):
    """The merged catalog and the keys both sides changed differently."""
    merged = dict(ours)
    conflicts = []
    base_strings, our_strings, their_strings = base.get("strings", {}), ours.get("strings", {}), theirs.get("strings", {})
    strings = dict(our_strings)
    keys = list(our_strings) + [k for k in their_strings if k not in our_strings]
    keys += [k for k in base_strings if k not in our_strings and k not in their_strings]
    for key in keys:
        original, mine, other = base_strings.get(key), our_strings.get(key), their_strings.get(key)
        if mine == other:
            value = mine
        elif mine == original:
            value = other
        elif other == original:
            value = mine
        else:
            conflicts.append(key)
            value = mine
        if value is None:
            strings.pop(key, None)
        else:
            strings[key] = value
    merged["strings"] = strings
    for field in ("sourceLanguage", "version"):
        if ours.get(field) != theirs.get(field) and ours.get(field) == base.get(field):
            merged[field] = theirs.get(field)
    return merged, conflicts


def main(argv):
    if len(argv) != 4:
        sys.stderr.write("usage: merge-xcstrings.py BASE OURS THEIRS\n")
        return 2
    base_path, ours_path, theirs_path = argv[1:]
    try:
        merged, conflicts = merge(load(base_path), load(ours_path), load(theirs_path))
    except (OSError, ValueError) as error:
        sys.stderr.write(f"merge-xcstrings: cannot read a version ({error}); leaving the conflict to git\n")
        return 1
    if conflicts:
        sys.stderr.write("merge-xcstrings: both sides changed " + ", ".join(repr(k) for k in conflicts[:5]) + "\n")
        return 1
    dump(merged, ours_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
