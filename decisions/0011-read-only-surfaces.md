# 0011. Importers, the command-line tool and AppleScript are read-only surfaces that never open the store

Status: Accepted

## Context
People switching from another clipboard manager want their curated clips, and scripts want to put text into Pesto and
read the latest clip back. Another app's library is untrusted input: large, malformed or hostile, and possibly holding
passwords the person excluded. A migration that writes models directly would bypass encryption at rest, masking,
classification and de-duplication. The store is encrypted under a key held in the login Keychain and bound to the app's
code identity, and SwiftData's SQLite store must not be opened by a second process. So import must run inside the app,
and anything a separate tool reads outside the store is plaintext that has to be justified and limited.

## Decision
**Importers read a copy, read-only, with bounds, then go through ingest.**
- **Entry point.** Settings → Data → Another app's library → Import: a menu of supported apps (`ImportSource`: Paste,
  Maccy, Alfred, CleanClip, PasteNow, CopyClip, PastePal, Pastebot, Clipy, Flycut, Unclutter), Other File and Snippets
  File. The person picks the file in an open panel; choosing it is the consent, and Pesto reads nothing it was not
  pointed at (finding an installed app asks LaunchServices, never the app's data). Each import first asks for Touch ID
  or the password (`ProtectedAction`, ADR 0003).
- **Read a copy.** A reader copies the file and any `-wal`/`-shm` to a temporary folder, opens the copy with SQLite
  `SQLITE_OPEN_READONLY`, and removes it afterwards. The original is never opened for writing. Bounds: 1 GB database,
  20,000 records, 50 MB per value (`ClipboardAppLibraryReader`; `PasteLibraryReader` has the same database and record
  limits and `maxRecordBytes` of 50 MB). A file that is not that app's library is `notRecognized`; one over a bound is
  `tooLarge`.
- **Paste** reads snippets with pinboard, title, time and source app; payloads decode through a stand-in for Paste's
  archive class under secure coding, so none of its code is used. Pinboards become collections with their clips pinned;
  Paste's history is opt-in and imported unpinned. Only the first pasteboard item of a multi-item copy is imported. A
  pinned Maccy item goes to a collection named "Pinned in Maccy".
- **Snippet files** (`SnippetPackReader`, the JSON a Raycast export or a TextExpander or Alfred converter writes): 5 MB
  (`maxBytes`), 1,000 entries (`maxEntries`), 20,000 characters each (`maxTextLength`). Single-brace placeholders
  convert to Pesto's; entries with none are pinned as clips and counted; unknown tokens are counted and left as typed.
  **Other File** (`GenericFileReader`: CSV, TSV, JSON or text): 20 MB, at most 20,000 rows, a clip over 1,000,000
  characters is left out and counted; nothing is imported until the person confirms the mapping.
- **Everything funnels through `PasteMigrator`** (a `@ModelActor`) into `StorageService.ingest` with the watcher's
  `PasteboardTypeDetector` priority, so encryption, masking, classification and content-hash de-duplication apply as for
  a live copy; it then pins into the matching collection. Never write a clip around `ingest`.
- **The capture rules still apply.** A record from an excluded app or marked concealed is skipped and counted (ADR
  0004).

**The command-line tool and AppleScript read a last-item file.** `LastItemStore` is the contract. The app writes
`last-item.json` in `AppPaths.supportDirectory` once a clip is fully judged (`StorageService.mirrorToLastItemFile`),
atomically and owner-only from creation (`PrivateFile.write`, mode 0600). It holds `id` (absent in older files),
`preview`, `type`, `timestamp` (ISO-8601) and `sourceApp`. There is no XPC service and no second process on the store.
- A clip with a sensitivity verdict is never written. With the History Lock on nothing is written and the file is
  cleared; the lock, deleting that clip (`clear(ifItemID:)`), clearing history, a wipe and key recovery remove it. The
  tool cannot ask for Touch ID, so under the lock `pesto last` reads nothing and says so. The file is a documented
  plaintext exception to encryption at rest (ADR 0002).
- **`pesto`** (`PestoCLI`, `make build-cli`, `make install-cli`): `pesto copy [--concealed] <text>` (or stdin, preferred
  for secrets since arguments show in `ps`) writes to the system pasteboard and Pesto's watcher captures it, so Pesto
  must be running; `--concealed` marks it so Pesto drops it. `pesto last [--json]` prints the preview or `id`,
  `preview`, `type`, `timestamp`, `sourceApp`. `pesto install` links the tool into `/usr/local/bin`, or `~/.local/bin`
  when that is not writable, replacing only a symbolic link (`CLIInstall.mayReplace`). It has no search, paste or
  delete.
- **AppleScript** (`Sources/Resources/Pesto.sdef`; `NSAppleScriptEnabled` and `OSAScriptingDefinition` in `Info.plist`;
  command codes exactly 8 characters): `copy item`, `get last item`, `search history` (previews among the newest 200
  clips, newest first, at most 20), `paste item` (by id), `list collections` and `clear history` (range `hour`, `today`
  or `all`; always confirmed in an alert, keeps pinned clips). Commands reach app state through `ScriptingContext`,
  never `NSApp.delegate as? AppDelegate`. Every command that reads or pastes history returns nothing while the History
  Lock is on or the app has not finished launching (`ScriptingContext.historyIsAccessible`).

## Consequences
- Re-running an import does not duplicate (ingest bumps the existing item), identical content in one run imports once,
  sensitive clips arrive masked. Nothing is written back to the source app, and no cleartext intermediate file exists.
- The last-item fields and path are a contract; an incompatible change needs a new decision. A script cannot get past
  the lock or a masked clip; it reads only what the shelf shows at rest.
- Schemas other than Paste's come from published data models and synthetic fixtures, and are unverified against real
  libraries until someone imports one.
- Tests: `PasteLibraryReaderTests`, `PasteMigratorTests`, `ClipboardAppReadersTests`, `ClipboardAppSourceTests`,
  `GenericFileReaderTests`, `LastItemStoreTests`, `CLIInstallTests`, `ClearRangeTests`, `DelegateCastTests`.

## Docs affected
`docs/guide/moving-from.md`, `docs/guide/automation.md`, `docs/guide/privacy-and-security.md`,
`docs/feature-reference.md`.
