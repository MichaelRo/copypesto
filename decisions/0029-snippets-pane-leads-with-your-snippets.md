# 0029. The Snippets pane leads with the person's snippets, and the placeholder reference is folded

Status: Accepted

Relates to [0017](0017-smart-snippets.md) and [0012](0012-settings-and-shortcuts.md) only through the pane's layout. Nothing about storage, sync, the network or how a snippet is expanded changes.

## Context
The pane opened with a reference table of ten placeholders. The person's own snippets and the starters sat below the fold, so the pane that exists to manage snippets showed a manual first. The table matters while writing a snippet, and the editor sheet already has its own placeholder menu.

## Decision
- The order is **Your snippets**, **Starters**, **From your clips**, **Placeholders you can use**, **Remember fill-in values**, **Suggestion statistics**.
- The placeholder reference is one disclosure row, closed by default, a `DisclosureGroup` (reachable by the keyboard and VoiceOver). The grid keeps its label "Placeholders you can use in a snippet", and its explanatory line ("Filled in when you paste…") moves inside the disclosure, because shown under a closed row it would read as orphaned.
- No section, identifier, footer or indexed row is removed. The search index reaches the pane for "placeholder" through the Snippets entry (a pane-level entry); no indexed row sits inside the folded section, so a search result never lands on a hidden row.
- `SnippetsPaneOrderTests` pins the order and the folded, closed default.

## Consequences
- The pane's picture (`settings-snippets`) changes and is retaken with the others.
- A person looking for the token list opens one row; the editor's Insert menu is unchanged.

## Docs affected
- `docs/guide/settings.md` (the Snippets order)
- `decisions/README.md` (this record in the table)
