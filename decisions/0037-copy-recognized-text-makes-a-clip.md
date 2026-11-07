# 0037. Copy Recognized Text copies the text as a clip of its own, and the picture stays where it is

Status: Accepted

Nothing about the network, storage, backup or sync formats changes. It supersedes one sentence of ADR 0034: the write "goes through `AppState.writeText`, so the watcher does not take it up again, and the clip moves to the front like any other copy".

## Context
Copy Recognized Text put the picture's text on the clipboard through the write gate, so the watcher skipped it, and then moved the picture to the front of the history (`noteCopied`). The person copied text, not the picture: the picture jumped to the front, and the text they copied was in no clip, so it was gone from the history as soon as they copied something else.

## Decision
- **The text is written as an ordinary copy, off the write gate** (`AppState.copyRecognizedText(of:)`, the way the AI-result Copy button writes), so the pasteboard watcher captures it like any copy and it becomes a text clip at the front. The text goes through every check a copy goes through: classification (a link or a color stays one), the secret scan, exclusion rules, the paused state.
- **The picture is not moved.** Copying its text is not a use of it, so nothing calls `bringToFront` on it.
- **Text that is already a clip** is not stored twice: the existing clip moves to the front (`popExistingDuplicate`, the same as copying that text anywhere).
- **A second click within two seconds** adds nothing (`lastIngestedHash`).
- **When capture is paused**, or an excluded app is frontmost, the text is on the clipboard and no clip is made. Pause and exclusions win over the convenience; the picture stays where it is either way.
- **The new clip's source is the app that is frontmost when the watcher reads it**, like the AI-result Copy button's, not the picture's app.
- **What does not change:** which pictures offer the entry, the covered-card rules, the file that holds the text, and that a text that cannot be read writes nothing and says so (ADR 0034).

## Consequences
- The shelf gains a card when the text is copied: the focus ring and the hover card may shift by one card (a hand check, `docs/testing.md`).
- One more write that is not on the gate: `PasteboardWriteSourcesTests` already allows `AppState+Paste.swift`; `AGENTS.md` and `Sources/Core/Paste/CLAUDE.md` list it beside the others.
- Tested: the hosted `CopyRecognizedTextTests` (text on the board, not an own write, not protected, picture untouched, no text writes nothing) and `RecognizedTextIngestTests` (a new clip at the front, the picture's timestamp unchanged, the same text twice makes one clip).

## Docs affected
- `AGENTS.md`, `Sources/Core/Paste/CLAUDE.md` (the list of writes that are captured)
- `docs/guide/using-pesto.md`, `README.md`, `docs/testing.md`
- `decisions/README.md`
- the website: the guide page is synced from `docs/guide/` after merge
