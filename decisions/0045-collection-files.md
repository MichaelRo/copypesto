# 0045. A collection is shared as a `.pesto` file that carries its pictures, files and whole texts

Status: Accepted (owner request, 2026-11-13)

Extends ADR 0002 (what is sealed at rest), ADR 0003 (secrets), ADR 0008 (Undo) and ADR 0011 (importers go through `ingest`). Nothing they decide is reversed. The text-only collection file of earlier versions (version 1, `.json`) is replaced as the thing Pesto writes and stays readable.

## Context
Export Collection wrote a JSON file of text clips, each cut to its 500-character preview. A collection of screenshots, files or long snippets arrived as nothing, or as a stub. Import was reachable only from Settings, and a file the person received had no type, so double-clicking it did nothing. The owner asked for "a way to import a collection" from the shelf too, a file that carries pictures and files within size limits, and the backlog item "Shareable Collection Packs".

Checked while deciding:
- A version 1 export of a hidden or secret clip wrote its **masked preview** (`Hidden by 1Password`, `•••• 1234`) as an ordinary text clip, and an import turned that mask into a real clip. No real secret text was written, but the file was wrong and a hidden clip's title and note were exported with it.
- `StorageService` keeps one sealed blob per clip (`ClipboardBlob`) holding the bytes the clip was captured with, and its `mimeType` is the pasteboard type they came from. A **file clip is a file URL, not the file's contents**: Pesto never reads the file.

## Decision
**Format.** Version 2 is the same JSON (`version`, `collection`, `items`). Per item it adds two optional fields: `payloadType` (the type identifier the data was stored under) and `payload` (the data, base64). `previewText`, title, note, tags, pin, time and source app stay, so a version 1 reader still imports the text items. Unknown fields are ignored. A file from a version above 2 is refused. It is still **one JSON file**: a package folder is zipped badly by mail and AirDrop.

**What round-trips.** Text, code, links and colors (the whole text, not the preview); pictures in any format Pesto captures (PNG, TIFF, JPEG, HEIC, GIF, WebP, PDF, SVG) with their bytes; file clips as the **file reference**. A file clip arrives as a card that pastes the same path: it works on the same Mac or a shared volume and not on another Mac, because the file's contents are not in the file. Carrying contents would mean reading arbitrary files at export and writing files at import; that is a separate decision if the owner wants it. Formatting of a rich-text copy (RTF, HTML flavors) and a link's preview image do not travel; a picture's text is read again on the new Mac.

**This is a plain file the person chose to write**, as version 1 was: it is not sealed, and anyone who gets it can read it. The save panel is the consent, and the privacy guide says so.

**What is never written.** A clip with a sensitivity category (secret, credit card, hidden/credential copy from an allowed password manager), a clip not yet judged (`analysisPending`), and a text in which the detector finds a secret now. They are left out and counted, never masked into the file. A clip over the caps is left out and counted. A text clip whose data cannot be opened is exported as its preview, as before; any other kind is counted as unreadable.

**Caps.** One clip's data is at most `UndoPolicy.maxClipBytes` (4 MB; the same "a clip this size is not held" line), the whole file at most `HistoryExporter.maxImportBytes` (64 MB, the existing import bound). A file is checked by size before it is read, a base64 string by length before it is decoded, a picture by its header (at most 50 megapixels, since a byte limit does not bound a decode).

**Import** goes through `StorageService.ingest` (ADR 0011: the only path that seals under the history key, masks, classifies and dedupes; the importer needs a `StorageService`, so the app passes its own). Per item, in order: already here (id, tombstone, or the same content hash) is counted and skipped; a source app on the exclusion list is skipped and counted with the secrets (ADR 0004); a payload is checked (type on a list of capture types, valid base64, size, text is UTF-8, a file clip is a `file:` URL, a picture opens); then `ingest` with the file's id and time, no text rewriting and no look-alike dedupe. The kind comes from the data and its type, never from the file's `type`. The result is a value: imported, already here, too large, left out as sensitive, unreadable. An item without a payload (a version 1 file) takes the earlier text path, which now also counts what it skips. Undo is as before: one action for up to 200 clips, plus the collection if the import created it.

**The `.pesto` type.** Extension `pesto`, identifier `AppIdentity.bundleID + ".collection"` (`net.copypesto.pesto.collection`), exported in `Info.plist` conforming to `public.json` and `public.data`, with a Viewer document type and `LSHandlerRank` Owner. Export writes `<name>.pesto`; the import panels accept `.pesto` and `.json`.

**Opening from Finder, AirDrop or a double click.** `application(_:open:)` hands a file URL to the import flow. It is judged by name, kind and size alone (`CollectionFileType.openVerdict`), the History Lock is honored through `ProtectedAction` (Touch ID or the password; refused with a message otherwise), the file is summarized (name, clip count) without importing it, and an alert asks "Import “name”?" with Import and Cancel. Nothing is imported silently. A file chosen in an open panel skips the question (choosing it is the consent). Every path ends with a message saying what came in and what was left out.

**Where.** The shelf: right-click the + (New Collection) button for *Import Collection…*; one click still makes a new collection. Settings → Collections keeps its Import… button; both call `AppState.importCollection`, which closes the shelf before the panel as Export does.

## Consequences
- A shared collection now holds what the person sees, within 4 MB a clip. A collection of large screenshots will skip some, and says how many.
- A secret never reaches a shared file, even masked; a collection with some secrets exports fewer clips than it shows, and the message says so.
- A file clip imported on another Mac may point at nothing. The card still shows its name and the paste puts the path on the pasteboard.
- Importing runs OCR and the other background analysis for each picture, one batch of 25 at a time, so a big pack takes as long as copying that many pictures.
- The right-click on + is not discoverable. A visible control would crowd the chip bar that another change is rearranging; the Settings button and double-clicking a file are the other doors.
- Pesto registers as the owner of `.pesto`, so a double click opens it in the menu-bar app. The document has no icon of its own yet.

## Docs affected
`docs/guide/using-pesto.md`, `docs/guide/privacy-and-security.md` (Exports), `docs/guide/settings.md`, `README.md`, `decisions/README.md`. `docs/pictures.md` and the pictures are untouched (the + button looks the same).
