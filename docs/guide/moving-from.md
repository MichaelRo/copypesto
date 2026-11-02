# Moving from another app

Bring your clipboard history, pinned clips or snippets into Pesto from other apps.

## Before you switch
- **There is no iPhone or iPad app.** Pesto can keep your Macs in step through iCloud Drive (*Settings → Data → Sync with my
  other Macs*, off until you turn it on), but not a phone or tablet, so pinboards you share with an iPhone in Paste will not
  stay shared there. You can also keep one encrypted backup file per Mac and restore it by hand.
- **⌘⇧V may collide with your old app.** Paste also uses it. Quit the old app first, or record another shortcut in
  *Settings → Shortcuts*; the second app to start loses the key. Maccy's default is ⇧⌘C. Some apps use ⇧⌘V for "paste
  without formatting".
- **Search reads the first 500 characters of each clip**, with words, meaning and the text inside pictures. There is no
  regular-expression or fuzzy mode.
- **Your old app's ignored-apps list does not come across.** Pesto has its own exclusions (*Settings → Privacy*), and
  password managers are skipped by default.
- **Pesto keeps a month of clips by default** (*Settings → Data*). Imported history keeps its original dates, so the
  older part of a big import is removed at the next cleanup. The import tells you how many clips that is.

## How Pesto finds and imports your history
If another supported clipboard manager is installed when you finish setup, the shelf shows a one-time line offering to bring its history
over. With one app, *Import…* opens *Settings → Data* at that app's import. With several ("You have Paste and Maccy"), *Choose…* opens
*Settings → Data* at **Found on this Mac**, a card with a row for each app and its own *Import…* button; you import them one at a
time, and each asks for Touch ID and a file of its own, so nothing is merged blind. *Not Now* ends the offer for every app. Pesto
finds the apps by asking macOS where they are installed; it opens none of their data until you choose to import. The card stays in
*Settings → Data* whenever one is installed, and a row says how many clips it brought in until you quit Pesto.

Every import reads a copy of your library read-only and leaves the original app untouched. Your clips are encrypted on disk under your own Mac's key, and Touch ID or your account password is required before reading any files.

## Moving from Paste
*Settings → Data → Another app's library → Import… → From Paste…* reads a copy of your Paste library and leaves Paste unchanged. Each of its
pinboards becomes a collection, and those clips are pinned. You can also bring in its clipboard history; those clips
are not pinned, so your retention setting may remove the older ones. Clips you already have are skipped. Formatting
(bold, links, rich text) comes across with a clip, as it does when you copy one. What does not:
- A clip that sat in two pinboards ends up in one collection (the first it meets).
- Manual order inside a pinboard: clips are ordered by date, and a pinboard's color is replaced by a neutral one unless it
  is one of Paste's default boards.
- Copies Paste marked concealed or transient (a password manager's, for example) are skipped, as a live copy would be.
- Only the first item of a multi-item copy, and nothing that lives only in Paste's iCloud data: Pesto reads the library
  file on this Mac. The file chooser starts where Paste keeps it (the App Store, Setapp and direct versions are all
  looked for); it is a hidden folder, so press ⌘⇧. in the chooser if you have to look for it yourself.
The import tells you how many clips came in and how many were left out.

## Moving from Maccy or Alfred

*Settings → Data → Another app's library → Import…* has dedicated importers for Maccy and Alfred, and detects them automatically if installed.

### Maccy
*Settings → Data → Another app's library → Import… → From Maccy…* opens Maccy's library file (`Storage.sqlite` in `~/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/`). The file chooser opens directly in Maccy's folder.

Pesto copies the file to a sandbox and reads it read-only; Maccy's original file is never opened for writing and stays untouched.
- **What comes over:** Full clipboard history, rich text (RTF and HTML), web links, source application names, and original copy timestamps.
- **Pinned clips:** Pinned clips in Maccy are preserved and imported into a dedicated collection named **Pinned in Maccy**.
- **What is skipped:** Clips you already have in Pesto, copies marked concealed or transient (such as passwords from a password manager), and items older than your retention setting in *Settings → Data*.
- **Confirmation:** Before anything is written, a preview sheet shows the count of history clips, pinned items, and any clips that will be skipped.

### Alfred
*Settings → Data → Another app's library → Import… → From Alfred…* opens Alfred's clipboard database (`clipboard.alfdb` in `~/Library/Application Support/Alfred/Databases/`). The file chooser starts in Alfred's database folder.

Pesto reads a copy of the database read-only. Alfred can stay running while you import.
- **What comes over:** Text clips and copied file paths, along with their source application and original timestamps.
- **What is skipped:** Picture clips (Alfred stores images as transient thumbnail caches), duplicates, and concealed copies.
- **Snippets:** Alfred snippets use separate `.alfredsnippets` files; see *Moving snippets from another app* below to import snippets via JSON.
- **Confirmation:** The preview sheet reports how many clips were found before you confirm the import.

## Moving from other clipboard apps
*Settings → Data → Another app's library → Import…* also includes dedicated importers for eight other macOS clipboard managers. For each app, the file chooser opens directly in its default storage location, reads a copy read-only without modifying the original, and asks for Touch ID or your password before importing.

### CleanClip
Reads CleanClip's database (`CleanClip.sqlite`). Imports history with custom titles, source apps, and timestamps. Pinned clips are automatically organized into a collection named **Pinned in CleanClip**.

### PasteNow
Reads PasteNow's store. Imports plain text, rich text, and web links. Each Pastelist list becomes its own Pesto collection, preserving your categorization.

### CopyClip
Reads CopyClip's SQLite database (`library.sqlite`). Imports plain-text history with original timestamps and source application bundle identifiers.

### PastePal
Reads PastePal's database. Imports history items, and pinned clips go into a dedicated collection called **Pinned in PastePal**.

### Pastebot
Reads Pastebot's database. Imports plain text, rich text, web links, and source app metadata.

### Clipy
Reads clips from Clipy's database, bringing across copied text and snippet items.

### Flycut
Reads Flycut's preferences store. All clip history is preserved, and marked favorites go into a collection called **Favorites in Flycut**.

### Unclutter
Reads clips and favorites from Unclutter's clipboard storage folder. Saved favorites become a **Favorites in Unclutter** collection.

## Raycast
Raycast encrypts its local clipboard database with SQLCipher using a key stored in your login Keychain, so Pesto cannot read its database directly. You can import Raycast snippets via JSON export: see *Moving snippets from another app* below.

## Moving anything else
Try *Other File…* first (see above). If your app's export does not fit, Pesto also reads the JSON that its own *Export History* writes, so a script can build one. The file is a JSON array of clips:

```json
[
  {
    "id": "6A8C5B0E-2B2F-4D43-9E8C-5C1D3A0F7E11",
    "timestamp": "2026-10-16T09:30:00Z",
    "type": "text",
    "previewText": "the clip's text",
    "sourceApp": "Safari",
    "sourceBundleID": "com.apple.Safari",
    "customTitle": null,
    "userNote": null,
    "tags": [],
    "isPinned": false
  }
]
```
`type` is `text`, `code`, `url` or `color`; only text can be imported this way, and only its first 500 characters.
Dates are ISO 8601 and `id` is a new UUID for each clip. To bring in a library with pictures or full text, ask for an
importer for that app (`SUPPORT.md` says where) and attach a small sample file.

## Moving snippets from another app
*Settings → Data → Another app's library → Import… → Snippets File…* reads the JSON file Raycast exports (Pesto does not
read Alfred's own `.alfredsnippets` file or TextExpander's, and has no abbreviation expansion: a snippet is a pinned
clip you paste from the shelf). Single-brace placeholders such as `{date}`, `{clipboard}` and `{uuid}` become Pesto's `{{date}}`, `{{clipboard}}` and `{{uuid}}`.
A snippet with no placeholder is pinned as an ordinary clip, and one that uses something Pesto does not fill in, such as
`{selection}`, keeps that text as typed; the sheet counts both.

## Moving from an app that is not listed
*Settings → Data → Another app's library → Import… → Other File…* reads a CSV, JSON or text file of clips, which most clipboard
managers can export. Pesto asks for Touch ID, then for the file, then shows what it found: for a CSV or a JSON list, which
column is the clip's text, when it was copied and whether it is pinned (it picks them by name when it can; a column you
do not choose is never read); for a text file, whether one clip is a block between blank lines, a line, or a block between
lines of dashes. *Continue* shows the usual import preview with its counts, and nothing comes in until you press *Import*.
Rows with no date keep the file's order and are dated now; pictures and files are not imported, secrets are masked as on a copy,
and clips you already have are skipped.

