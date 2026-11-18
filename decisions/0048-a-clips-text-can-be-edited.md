# 0048. A text clip's content can be edited; it stays the same clip, sealed and judged again, one Undo, one sync change

Status: Accepted (owner request, 2026-11-15)

Extends ADR 0002 (sealed at rest), ADR 0003 (secrets), ADR 0008 (undo), ADR 0018 (sync) and ADR 0021 (order). Nothing
they decide is reversed.

## Context
Only a snippet's text could be changed (`updateSnippet`, Settings → Snippets). On iPhone and iPad a person fixes a typo
in a copied address or trims a link far more often than they write snippets, and the Mac will want the same thing.
Checked while deciding: ingest dedupes by content hash and sync treats one plain SHA-256 as one clip on every device
(two local clips with the same text would make a remote device fold one into the other); an item record already carries
the id, the payload and the curation, and `applySync` replaces the text of a clip it holds under the same id (the path a
snippet edit and a double ⌘C already use).

## Decision
- **One Core path**, `StorageService.updateText(id:text:)`, for text, code, link and color clips that are judged (not
  pictures, files or a clip still being analyzed). `updateSnippet` shares its sealing (`sealText`) and keeps its own
  rules (text or code only, a title, the Snippets collection). The Mac can call the same function; it has no UI for it
  yet.
- **What changes:** the blob, sealed under the clip's id with no rich text left over; the content hash; the kind and the
  detected language, read again by `ContentClassifier`; the byte size and text length; the secret scan (a secret added
  is masked with its preview, a secret removed is shown; a kept password-manager copy stays a hidden credential,
  ADR 0004); the sealed preview (a color's stays plain, as at ingest); the search vector and the text signature, cleared
  and computed again; a link's page title, site name and preview picture, dropped. Rules that rewrite a copy are not
  applied: the person typed this text.
- **What stays:** title, note, tags, collection, place in a collection, pin, shortcut, first copy and `timestamp`. An edit
  is not a use (ADR 0021), so it does not move the clip.
- **Refused:** an empty text, the same text (nothing happens), a text over `ClipSizePolicy`'s limit (its message), and
  a text another clip already holds (`sameAsAnother`: "Another clip already has this text."), so the history keeps one
  clip per content and sync never sees two. A hidden secret is edited only after Show; that rule is the caller's.
- **Undo:** one entry, "Changed the text" (`UndoLabel.editText`), holding the sealed clip before and after
  (`ClipReplacement`); undo writes the old ciphertext back byte for byte, and both directions skip a clip whose target
  text another clip took meanwhile. `UndoPolicy` still decides what is never held (an expiring clip, a credential).
- **Sync:** the content hash is part of the sync fingerprint, so the save stamps the clip and it goes out as an item
  record under the same id; another device replaces that clip's text and keeps its id and curation. The wire format is
  unchanged. A device's own derived data for that clip (its paste days, fill-in memory) does not survive on the device
  that receives the edit, as with a snippet edit.

## Consequences
- The plaintext never touches the store (`ClipTextEditOnDiskTests`), and `ClipTextEditTests` and `SyncTextEditTests`
  pin the rest.
- iOS shows Edit Text in the detail for a clip it can edit; Save and Cancel close the editor, so outside it a tap still
  selects text.
- The Mac's Undo words gain "Changed the text" and "Text Change" for the day its UI calls this.

## Docs affected
`docs/design/ios-library.md`, `Sources/Core/Storage/CLAUDE.md`, `decisions/README.md`. The README and the guide say
nothing until the Mac offers it or the iPhone app is released (ADR 0046).
