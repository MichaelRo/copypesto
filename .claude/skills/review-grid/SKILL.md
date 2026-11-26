---
name: review-grid
description: Generate a scoped multi-agent review grid for the current diff and execute triggered specialist reviewers sequentially.
---

# Scoped Multi-Agent Review Grid

Use this workflow after implementing a change and before opening or merging a PR.

## 1. Generate the grid & run static guards

```bash
python3 scripts/review_grid.py --base origin/main --check
```

For machine-readable lens prompts:

```bash
python3 scripts/review_grid.py --base origin/main --json
```

## 2. Run triggered lenses sequentially

To stay well within token and context budgets, dispatch **only** the triggered lenses and run them **one at a time** (wait for each specialist to return before launching the next):

1. Read each lens's `files`, `invariants`, and `prompt` from `review_grid.py`.
2. Launch a read-only specialist subagent for the first triggered lens with its scoped file list and invariants.
3. Wait for its findings before launching the next triggered lens.
4. Fix every confirmed defect with a failing test first, re-run the lens's targeted verification commands, and run `make lint`.
