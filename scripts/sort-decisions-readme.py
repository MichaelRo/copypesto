#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Sort the ADR index table in decisions/README.md ascending by ADR number.

`.gitattributes` sets `decisions/README.md merge=union`, which keeps both sides' new rows cleanly without git
conflicts, though two concurrent PRs can leave rows out of number order or duplicated. Run this script (or
`make sort-decisions`) to keep the table sorted, or `--check` to verify order and uniqueness without modifying.
"""
import argparse
import pathlib
import re
import sys

ROW_RE = re.compile(r"^\| \[(\d{4})\]\([^)]+\) \|")


def sort_decisions_readme(text: str) -> tuple[str, bool, list[str]]:
    """Return (updated_text, changed, diagnostics) for decisions/README.md."""
    lines = text.splitlines(keepends=True)
    row_indices: list[int] = []
    parsed: list[tuple[int, str]] = []
    diagnostics: list[str] = []

    for idx, line in enumerate(lines):
        match = ROW_RE.match(line)
        if match:
            row_indices.append(idx)
            parsed.append((int(match.group(1)), line))

    if not row_indices:
        return text, False, []

    seen: set[str] = set()
    unique_rows: list[tuple[int, str]] = []
    for num, line in parsed:
        if line in seen:
            diagnostics.append(f"duplicate row for ADR {num:04d}")
            continue
        seen.add(line)
        unique_rows.append((num, line))

    sorted_rows = sorted(unique_rows, key=lambda pair: pair[0])

    expected_numbers = [num for num, _ in sorted_rows]
    actual_numbers = [num for num, _ in parsed]
    if actual_numbers != expected_numbers and not diagnostics:
        diagnostics.append(f"ADR rows out of order: {actual_numbers} != {expected_numbers}")

    first, last = row_indices[0], row_indices[-1]
    # Preserve any non-row lines only if somehow interleaved; normally all rows form one contiguous block.
    interleaved = [lines[i] for i in range(first, last + 1) if i not in set(row_indices)]
    new_block = [line for _, line in sorted_rows] + interleaved
    new_lines = lines[:first] + new_block + lines[last + 1 :]
    updated = "".join(new_lines)
    return updated, updated != text, diagnostics


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Sort ADR index rows in decisions/README.md.")
    parser.add_argument("--check", action="store_true", help="Exit 1 if out of order or duplicated without editing.")
    parser.add_argument(
        "path",
        nargs="?",
        default="decisions/README.md",
        help="Path to decisions README (default: decisions/README.md).",
    )
    args = parser.parse_args(argv)

    target = pathlib.Path(args.path)
    original = target.read_text(encoding="utf-8")
    updated, changed, diagnostics = sort_decisions_readme(original)

    if args.check:
        if changed:
            for msg in diagnostics:
                sys.stderr.write(f"sort-decisions-readme: {msg}\n")
            sys.stderr.write("Run 'make sort-decisions' to sort decisions/README.md.\n")
            return 1
        return 0

    if changed:
        target.write_text(updated, encoding="utf-8")
        print(f"Sorted {target} ({', '.join(diagnostics) if diagnostics else 'updated'}).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
