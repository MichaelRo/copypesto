#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Sort the ADR index table in decisions/README.md ascending by ADR number.

`.gitattributes` sets `decisions/README.md merge=union`, which keeps both sides' new rows cleanly without git
conflicts, though two concurrent PRs can leave rows out of number order or duplicated. Run this script (or
`make sort-decisions`) to keep the table sorted, or `--check` to verify order and uniqueness without modifying.
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

ROW_RE = re.compile(r"^\| \[(\d{4})\]\([^)]+\) \|")


def _find_table_span(lines: list[str]) -> tuple[int, int] | None:
    """Return [start, end) line indices of the contiguous ADR table rows."""
    start = None
    for idx, line in enumerate(lines):
        if ROW_RE.match(line):
            start = idx
            break
    if start is None:
        return None
    end = start
    while end < len(lines) and ROW_RE.match(lines[end]):
        end += 1
    return start, end


def sort_decisions_readme(text: str) -> tuple[str, bool, list[str]]:
    """Return (updated_text, changed, diagnostics) for decisions/README.md."""
    lines = text.splitlines(keepends=True)
    span = _find_table_span(lines)
    if span is None:
        return text, False, []

    start, end = span
    parsed: list[tuple[int, str]] = []
    for line in lines[start:end]:
        match = ROW_RE.match(line)
        if match:
            normalized = line if line.endswith("\n") else f"{line}\n"
            parsed.append((int(match.group(1)), normalized))

    seen_lines: set[str] = set()
    by_number: dict[int, str] = {}
    unique_rows: list[tuple[int, str]] = []
    diagnostics: list[str] = []
    has_conflict = False

    for num, line in parsed:
        if line in seen_lines:
            diagnostics.append(f"duplicate row for ADR {num:04d}")
            continue
        seen_lines.add(line)
        if num in by_number:
            diagnostics.append(f"conflicting rows share ADR number {num:04d}")
            has_conflict = True
        else:
            by_number[num] = line
        unique_rows.append((num, line))

    sorted_rows = sorted(unique_rows, key=lambda pair: pair[0])
    expected_numbers = [num for num, _ in sorted_rows]
    actual_numbers = [num for num, _ in parsed]
    if actual_numbers != expected_numbers and not has_conflict:
        diagnostics.append(f"ADR rows out of order: {actual_numbers} != {expected_numbers}")

    had_trailing_nl = text.endswith("\n")
    new_block = [line for _, line in sorted_rows]
    new_lines = lines[:start] + new_block + lines[end:]
    updated = "".join(new_lines)
    if not had_trailing_nl and end == len(lines) and updated.endswith("\n"):
        updated = updated[:-1]
    return updated, (updated != text or has_conflict), diagnostics


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Sort ADR index rows in decisions/README.md.")
    parser.add_argument("--check", action="store_true", help="Exit 1 if out of order or duplicated without editing.")
    parser.add_argument(
        "path",
        nargs="?",
        default="decisions/README.md",
        help="Path to decisions README, or '-' for stdin with --check (default: decisions/README.md).",
    )
    args = parser.parse_args(argv)

    if args.path == "-":
        if not args.check:
            sys.stderr.write("sort-decisions-readme: '-' (stdin) may only be used with --check\n")
            return 2
        original = sys.stdin.read()
        target = None
    else:
        target = pathlib.Path(args.path)
        original = target.read_text(encoding="utf-8")

    updated, needs_attention, diagnostics = sort_decisions_readme(original)

    if args.check:
        if needs_attention:
            for msg in diagnostics:
                sys.stderr.write(f"sort-decisions-readme: {msg}\n")
            sys.stderr.write("Run 'make sort-decisions' to sort decisions/README.md.\n")
            return 1
        return 0

    if target is not None and updated != original:
        target.write_text(updated, encoding="utf-8")
        print(f"Sorted {target} ({', '.join(diagnostics) if diagnostics else 'updated'}).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
