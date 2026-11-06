# 0030. The Snippets pane shows the placeholder reference

Status: Accepted

Supersedes the folded reference of [0029](0029-snippets-pane-leads-with-your-snippets.md). Nothing about storage, sync, the network or how a snippet is expanded changes.

## Context
0029 folded the placeholder table to put the person's snippets first. The table turned out to be clear and useful to people writing a snippet, and a closed row hid it.

## Decision
- The order is unchanged: **Your snippets**, **Starters**, **From your clips**, **Placeholders you can use**, **Remember fill-in values**, **Suggestion statistics**.
- **Placeholders you can use** is an ordinary section with a header, open always: the grid, its VoiceOver label, its explanatory line and a *See the guide* link to the Snippets section of the guide (`https://copypesto.net/docs/settings/#snippets`, the existing `copypesto.net` host).
- The `DisclosureGroup` and its state are removed; the fold was never a `Setting`.
- `SnippetsPaneOrderTests` pins the order, the shown section and the link.

## Consequences
- The pane's picture (`settings-snippets`) changes and is retaken with the others.

## Docs affected
- `docs/guide/settings.md`, `docs/testing.md` (the Snippets hand check)
- `decisions/README.md` (this record in the table)
