# Copy guide: words, tone and localization

The same thing used to be called a "clip", an "item" and a "card" in different places, and "sensitive" meant two
different things. This is the vocabulary to use in the UI,
the docs and the website. Change a term here first, then everywhere.

## Glossary
| Say | Means | Do not say |
|---|---|---|
| **clip** | One saved copy of anything (text, link, picture, file, color) | item, entry, snippet (see below), record |
| **card** | A clip's picture on the shelf. Only in layout words: "card size", "clip cards" | using "card" for the clip itself |
| **shelf** | The bottom drawer opened with ⌘⇧V | overlay, drawer, panel, popup |
| **history** | Every clip Pesto has saved | clipboard log |
| **pinned clip** | A clip kept forever and exempt from retention (can have a ⌃1–⌃9 shortcut) | favorite, starred |
| **floating window** | The always-on-top copy of the shelf, from the menu bar. Not "pinned window": it reads like a window of pinned clips | pinned window |
| **collection** | A named group of clips (static or smart) | pinboard, folder, tag group |
| **snippet** | A saved template with `{{placeholders}}`, expanded at paste time. Not a synonym for a clip | using it for ordinary clips |
| **secret** | Something that looks like a password, key, token or card number. Secrets are **masked** on the card and never indexed | "sensitive" for this |
| **sensitive** | Content the blur filter hides (adult content). Menu pair: **Mark as Sensitive** / **Mark as Not Sensitive**; a revealed card offers **Hide Again** | "NSFW" anywhere the user can see it |
| **blur / hide / show** | The three content-filter modes | |
| **paste** / **copy** | Paste = put a clip into the app you were using; copy = put it on the clipboard | "insert", "send" |
| **Paste All** | The selection action that joins the selected text clips with a blank line and pastes them at once; it saves no new clip. ⌘P | Merge |
| **Paste One by One** | The selection action that pastes the first clip when the shelf closes and the next one on each plain ⌘V. ⇧⌘P | Stack, paste stack |
| **Append** | The optional second ⌘C that adds the new copy to the previous clip | merge |
| **picture** | A copied image, in prose ("the text inside pictures"). "Image" only inside a name: Describe Image, the Image type chip | "image" in sentences |
| **Pesto** | The app. Never "the app" in its own UI | |

The rule for pairs: state and its opposite share a verb ("Mark as Sensitive" / "Mark as Not Sensitive", like Mark as
Read / Mark as Unread in Mail). A menu item that toggles a flag is worded for what it will do, not what the flag is.

## Arrows in paths
The guide writes a place in Settings as an arrow path, *Settings → Data → Another app's library*. The UI never does: a
label names one thing. The website's own copy follows its own voice document and only the synced guide keeps the arrows.

## Spelling
The UI, the docs, the guide and the website use American English: color, license, organize, summarize, sanitization,
gray, canceled. Names keep their own spelling (Apple Intelligence, notarized). File names and URLs are not renamed for
spelling. Search keywords may list both spellings ("colour", "sanitise") so either one finds the setting.

## Voice
- Plain, calm, short. Say what will happen: "This deletes clips from the last hour. Pinned clips are kept."
- Sentences end with a period in captions and alerts; buttons and menu items do not.
- In the app, Title Case for menu items and buttons, as macOS does ("Mark as Sensitive", "Show Recovery Key…", "Clear
  Everything"). Sentence case for labels, section headers, descriptions and alerts ("Keep clips for", "Floating window",
  "Older clips are removed automatically."). Proper names and settings pane names keep their capitals. Apple's own
  System Settings capitalizes section headers; the HIG leaves the choice to each app, so Pesto's headers follow this
  guide, and a header that breaks it is a bug. The title of a sheet or window is Title Case too ("Set Up Backup",
  "Restore from Backup", "New Snippet").
- Never promise what is not there. There is no sync in v1, so no string may mention synced devices; the sensitive-image
  filter is best-effort, so it says so.
- Errors say what failed and what to do next: "Couldn't delete the clip." plus a next step when there is one.
- Numbers with units and plurals go through the localization system, never string concatenation.

## Localization
- Counted words go through `CountText` or `String(localized: "\(count) clips …")`, with the one and other forms in
  `Sources/Resources/Localizable.xcstrings`; `VocabularyTests` fails on `(s)` and on a count ternary.
- SwiftUI `Text("literal")`, `Button("literal")` and `Toggle("literal")` are localizable through the String Catalog. The
  catalog holds only the plural sentences: the project does not extract the other literals (`SWIFT_EMIT_LOC_STRINGS` is
  off, checked on 2026-10-22: a build writes no `.stringsdata` for Swift files), so the first translation starts by
  turning extraction on and reviewing what it adds. Strings built in code (AppKit alerts, menu titles in `AppDelegate`) need
  `String(localized:)`. The catalog has English only so far. In a right-to-left layout the arrow keys and the collection slide follow
  the row (D-08); the rest of right-to-left needs its own pass when there is a translation (the shelf scrolls
  horizontally).
