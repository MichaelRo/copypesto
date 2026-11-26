# 0075. A clip becomes a snippet in place

Status: Accepted (owner, 2026-11-26, backlog: "convert a text clip to a snippet")

Amends ADR 0071's consequence that Make Snippet with fill-ins and a larger picture or file preview are backlog, and
the iPhone's Save as Snippet (ADR 0017's snippets, made a menu action in #204).

## Context
A snippet is a pinned clip whose text holds a `{{placeholder}}` (`ClipboardItem.isTemplate`); there is no snippet
model. The Mac had no way to make one from a clip except the shelf's suggestion and the Settings list, both of which
open the editor in Settings and save a *new* clip once the text changes, leaving the original beside it. The iPhone's
Save as Snippet saved at once: text with no `{name}` was only pinned while the toast said "Saved as a snippet", so
the clip never appeared in Snippets; text with `{name}` became a second clip.

## Decision
- **Make Snippet turns the clip itself into the snippet.** `StorageService.convertToSnippet(id:title:text:)` seals the
  new text as an edit does (ADR 0048), pins the same clip and keeps its note, tags, collection and place. One Undo
  (`UndoEntry.Kind.snippetsMade`, "Make Snippet") takes back the text, the title and the pin together; Redo makes it a
  snippet again.
- **The text must ask for something.** Without a `{{placeholder}}` the conversion is refused with words that say so,
  so a pinned clip is never called a snippet. Callers turn `{name}` into fill-ins first (`FillInParser`), as the
  editors already do.
- **Who offers it is one rule** (`TextEditPolicy.offersMakeSnippet`): visible text or code that is not a secret, not
  still being judged and not a snippet already. A secret is never converted, and Settings never seeds its editor from
  one.
- **On the Mac it happens inside the Clip window**: *Make Snippet…* (or *Edit as Snippet…* for a snippet) swaps the
  text for the snippet editor, seeded with the text as typed; Esc or Cancel goes back to the text without closing the
  window. The editor is the Settings one (`SnippetEditorView`), so there is one editor to learn.
- **On the iPhone, *Make Snippet…* opens the snippet editor** on the clip's whole text and saves through the same
  conversion; the menu no longer saves without showing the text.
- **The Clip window shows a clip it does not edit larger** (`ClipInspectorPreview`): a picture at up to 1,024 px
  fitted to the pane, one file as its Quick Look preview, several files as a list; the cover rules of ADR 0071 stand.
- The Settings editor's suggestion seed reads the clip's whole text, not its 500-character preview.

## Consequences
- A snippet made from a clip is the same row on every Mac and iPhone that syncs; there is no duplicate to clean up.
- Making a snippet from several look-alike clips (the shelf's suggestion, Similar Clips on the iPhone) still makes a
  new clip, because no one clip is the template.
- The Make Snippet flow is covered by `ClipWindowUITests` on the Mac and `SnippetFillUITests` on the iPhone.

## Docs affected
- `docs/guide/using-pesto.md`, `README.md`, `decisions/README.md`
