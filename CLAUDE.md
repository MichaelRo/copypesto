@AGENTS.md

# Claude Code only

- Recipes in `.claude/skills/` load as skills (`pasteboard-type`, `smart-pinboard`).
- A PostToolUse hook in `.claude/settings.json` rejects a raw `NSHostingView` after every Edit or Write.
- Personal overrides go in `CLAUDE.local.md` and `.claude/settings.local.json`; never commit them.
