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

Every import copies the database to a temporary folder that Pesto removes afterwards, opens the copy read-only and leaves the original app untouched. Before anything is saved, a preview sheet shows the counts of pinned clips, history clips, skipped clips and clips older than your retention setting, and waits for your confirmation. Clips you already have are skipped, Pesto's exclusion and secret-masking rules apply as on a live copy, and every imported clip is encrypted on disk under your Mac's key.

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
A library of more than 20,000 clips, or a file over 1 GB, is refused whole ("That file is too large to import"), pinboards included. Trim Paste's history first.

The import tells you how many clips came in and how many were left out.

## Moving from Maccy or Alfred

*Settings → Data → Another app's library → Import…* has dedicated importers for Maccy and Alfred, and detects both automatically if installed.

### Maccy
*Settings → Data → Another app's library → Import… → From Maccy…* opens Maccy's library file (`Storage.sqlite` in `~/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/`). The file chooser starts in Maccy's folder, and Maccy can stay running while you import.
- **What comes over:** All stored pasteboard types (plain text, rich text, HTML, links and pictures), source apps and original copy times.
- **Pinned clips:** Pinned clips go to a collection called "Pinned in Maccy".
- **What is skipped:** Clips you already have, copies marked concealed or transient, and clips with no readable content.

### Alfred
*Settings → Data → Another app's library → Import… → From Alfred…* opens Alfred's clipboard database (`clipboard.alfdb` in `~/Library/Application Support/Alfred/Databases/`). The file chooser starts in Alfred's database folder, and Alfred can stay running while you import.
- **What comes over:** Text clips and copied file paths, with their source apps and original copy times.
- **What is skipped:** Pictures (which Alfred stores outside the table), clips you already have and concealed copies.
- **Snippets:** Alfred snippets use separate `.alfredsnippets` files; see *Moving snippets from another app* below to import snippets from a JSON file.

## Moving from other clipboard apps
*Settings → Data → Another app's library → Import…* also includes dedicated importers for eight other macOS clipboard managers. For each app, the file chooser starts in its default folder, Pesto reads a copy read-only and leaves the original untouched, and the preview sheet shows what was found before you confirm.

### CleanClip
Reads CleanClip's database (`Storage.sqlite` in `~/Library/Application Support/CleanClip/`). Brings in stored clip types, custom titles, source apps and copy times. Pinned clips go to a collection called "Pinned in CleanClip".

### PasteNow
Reads PasteNow's database (`PasteNow.sqlite`). Brings in plain text, rich text, links, titles, source apps and copy times. Each Pastelist list becomes its own collection.

### CopyClip
Reads CopyClip's database (`copyclip.sqlite` or `CopyClip.sqlite`). Brings in plain-text clips with their original copy times.

### PastePal
Reads PastePal's database (`PastePal2.sqlite` or `PastePal.sqlite`). Brings in plain-text clips, source apps and copy times. Pinned clips go to a collection called "Pinned in PastePal".

### Pastebot
Reads Pastebot's database (`Pastebot.sqlite`). Brings in stored pasteboard types, custom titles, source apps and copy times.

### Clipy
Reads Clipy's database (`sqlite.db` in `~/Library/Application Support/com.clipy-app.Clipy/`). Brings in stored pasteboard types, titles and copy times.

### Flycut
Reads Flycut's preferences store (`com.generalarcade.flycut.plist`). Brings in plain-text clips, source apps and copy times. Favorites go to a collection called "Favorites in Flycut".

### Unclutter
Reads Unclutter's clipboard folder (`history.plist` and `favorites.plist`). Brings in text and PNG picture clips with their source apps and copy times. Favorites go to a collection called "Favorites in Unclutter".

## Moving from an app that is not listed
*Settings → Data → Another app's library → Import… → Other File…* reads a CSV, JSON or text file of clips, which most clipboard
managers can export. Pesto asks for Touch ID, then for the file, then shows what it found: for a CSV or a JSON list, which
column is the clip's text, when it was copied and whether it is pinned (it picks them by name when it can; a column you
do not choose is never read); for a text file, whether one clip is a block between blank lines, a line, or a block between
lines of dashes. *Continue* shows the usual import preview with its counts, and nothing comes in until you press *Import*.
Rows with no date keep the file's order and are dated now; pictures and files are not imported, secrets are masked as on a copy,
and clips you already have are skipped.

## Moving snippets from another app
*Settings → Data → Another app's library → Import… → Snippets File…* reads the JSON file Raycast exports (Pesto does not
read Alfred's own `.alfredsnippets` file or TextExpander's directly, and has no abbreviation expansion: a snippet is a pinned
clip you paste from the shelf). Single-brace placeholders such as `{date}`, `{clipboard}` and `{uuid}` become Pesto's `{{date}}`, `{{clipboard}}` and `{{uuid}}`. Raycast `{argument}` placeholders and TextExpander `%filltext`, `%fillarea`, `%fillpopup` and `%fillpart` fill-ins become snippets that ask when you paste.
A snippet with no placeholder is pinned as an ordinary clip, and one that uses something Pesto does not fill in, such as
`{selection}`, keeps that text as typed; the sheet counts both.

## Raycast
Raycast encrypts its local clipboard database with SQLCipher using a key stored in your login Keychain, so Pesto cannot read its clipboard history directly. You can import Raycast snippets via JSON export: see *Moving snippets from another app* above.

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
