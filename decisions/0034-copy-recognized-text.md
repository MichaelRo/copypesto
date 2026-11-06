# 0034. Copy Recognized Text: a picture's whole text is kept in its own sealed file

Status: Accepted

Nothing about the network, the backup file format or the sync file format changes. It amends one sentence of ADR 0009 (the hover card "takes the pointer only when its body scrolls").

## Context
Pesto reads the text in every picture on the device (ADR 0006) and, until now, kept only its first 500 characters, as the clip's sealed preview. A person who copies a screenshot of a page, a receipt or a slide could search by those words but not copy them. The text is too big for a column: every `@Query` loads every column of every clip (`Core/Storage/CLAUDE.md`).

## Decision
- **One sealed file per picture, `RecognizedTextStore`**, beside the link preview images: `recognized-text/<clip id>.bin`, AES-GCM under the install key, associated data `pesto.v2|<id>|recognized-text`, mode 0600. A file moved to another clip, or a link preview image moved here, does not open. Not a column, not `ItemMetadata`, not new `ClipboardBlob` columns (a schema change for every store) and not the rich-flavour slot (it is written back on a paste).
- **What is kept.** The text up to 100,000 bytes of UTF-8, cut on a character boundary (`RecognizedText.maxBytes`). A file exists only when the text is at least as long as the preview (500 characters), because a shorter text is its own preview, and never for a picture that holds a secret. The write happens after the clip is saved (`finishAnalysis`), so a failed save leaves no file. The preview, search and the search vector still use the first 500 characters.
- **The secret scan reads all of the kept text**, not the preview. Before this, a key lower than 500 characters into a screenshot was not masked; with a way to copy the text it would have been handed out. `SensitiveContentDetector.detectAnywhere` reads line by line and word by word up to 100,000 bytes (it stopped at 50,000).
- **When the entry is offered** (`RecognizedText.isOffered`, asked when the menu opens or the hover card is about to show, never while a card draws): a picture that is not hidden (even while shown), filtered or still being read, while the history is unlocked, and either has a file or has a preview shorter than 500 characters (the whole text). An older picture whose preview is exactly 500 characters and has no file may have been cut, so it is not offered; there is no backfill, because reading every old picture again would cost CPU for a feature few will use. A file that will not open writes nothing and says so; the preview is never a fallback.
- **Where it is.** **Copy Recognized Text** in the card's menu after Copy, a VoiceOver action, and **Copy Text** in the hover card of such a picture. A covered card (screen share, Hide Clip Contents, hidden, filtered) has none of them: the entry is not in `CardMenuItem.coveredAllowed`. The write goes through `AppState.writeText`, so the watcher does not take it up again, and the clip moves to the front like any other copy.
- **The hover card gets its first button, and so takes the pointer.** Copy Text is the accent text of the card, right-aligned on the "Text in the picture" line, 22 pt tall and at least 84 pt wide, with a wash behind it while the pointer is on it (read by a tracking area: SwiftUI's `onHover` is not reliable in a window that is never key) and "Copied" for two seconds after a click. Only a picture that offers the entry takes the pointer (`HoverCardHost.Request.takesPointer`, was `scrolls`), and it then stays open while the pointer crosses to it, as a card that scrolls does. The panel stays non-activating and never key; a click lands in it (`HoverCardClickTests`).
- **Backup and sync carry nothing new.** Restore and sync both ingest the picture again, which reads it again, so a restored or synced clip gets its full text, even from an older backup. A backup or sync record names no recognized text, so an older Pesto reads the new files and a secret-bearing text is not added to a synced folder.
- **Delete, Clear History, Clear Everything and Undo.** Deleting a clip deletes its file; Clear Everything removes the folder; Undo keeps the sealed file in memory with the clip (`ClipSnapshot.recognizedTextFile`, counted in its 16 MB) and puts it back.

## Consequences
- A picture costs up to 100 KB of disk more, sealed. Memory stays flat: 150 screenshots with 100 KB of text each left the footprint where 150 with 600 characters left it (`RecognizedTextMemoryTests`, Debug build on the developer Mac). Their reading took 8.1 s against 2.5 s in total, about 37 ms a picture in a Debug build, after the card is on the shelf and covered; reading the picture (hundreds of milliseconds) is still the long part.
- The text is plaintext in memory only while it is copied.
- The hover card is no longer button-free. Every card that is not a picture with text behaves as before.
- Older Pestos that restore a newer backup lose nothing; a newer Pesto that restores an older one reads the text again when the clip is ingested.

## Docs affected
- `docs/guide/using-pesto.md` (hover card, the menu, search line; synced to the website), `docs/guide/privacy-and-security.md`
- `README.md`, `docs/feature-reference.md`, `docs/testing.md` (hand checks)
- `AGENTS.md` (security invariant 2, the hover card line), `Sources/Core/Storage/CLAUDE.md`, `Sources/Features/Overlay/CLAUDE.md`
- `decisions/README.md`
