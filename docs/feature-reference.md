# Feature reference

The complete, detailed feature list (the [README](../README.md) has the short tour, and the [user guide](guide/README.md) explains how to use each part).

### Capture
- **Clipboard history** — captures text, code, pictures, files, URLs, colors
- **Source app tracking** — captures which app you copied from, with icon and accent color
- **On-device OCR** — pictures are scanned so text inside screenshots is searchable
- **Smart deduplication** — full-history keyed content hash (HMAC-SHA256 under a key derived from the install key) (30-second in-memory fast path + DB fetch) + perceptual hash (Hamming ≤ 5) for near-identical pictures; re-copying an existing clip moves it to the top without creating a duplicate
- **GIF support** — animated GIFs are captured and shown as picture clips (`com.compuserve.gif` / `public.gif`)

### Search & organization
- **Smart search** — full-text substring search + on-device semantic search (NLEmbedding, query > 8 chars); `@tag` or `@lang` prefix filters by tag or detected language; filter bar (type/date/source-app/Sensitive chips, plus Other Devices when copies from other devices are kept) appears while searching; recent-searches popover on empty field; "Rebuild" next to "Search index" in Settings → Data → Maintenance backfills every clip
- **Tags** — add free-form tags to any clip via the context menu; tag chips in the command bar let you filter by tag in one click
- **Files** — copy several files in Finder and they stay together as one clip, shown with their icon or a preview, name and folder; Pesto stores the location, never the contents, and flags files that have moved. A lone PDF or SVG is kept as a picture clip and pastes back unchanged.
- **Collections** — static and smart (predicate-driven) clip collections; smart collections support AND/OR groups with a visual rule builder; filter by type, source app, text, date, content shape (gif/code/link/curl/json), sensitivity, tag, or whether it came from another device; right-click any collection chip to Edit, Duplicate, Export, or Delete (Export Collection… is also in Settings → Collections, which imports the file back); click **+** in the chip bar to create a new collection without leaving the shelf
- **Entity quick actions** — phone numbers, emails, addresses, dates ("Add to Calendar", via a calendar file, no permission needed), carrier tracking numbers (UPS, USPS, FedEx, DHL, checked by their check digit; opened in your browser), coordinates (decimal with a comma, semicolon or space, or degrees-minutes-seconds) and links inside text get actions in the card context menu

### Paste
- **Three-tier paste** — Accessibility direct write → CGEvent keystroke → manual toast fallback
- **Quick paste** — a shortcut you record in Settings → Shortcuts (none by default) pastes the previous copy (the second most recent) without opening the shelf
- **Paste as plain text** — `⌃⌥⌘V` pastes what is on the clipboard now, stripped of formatting (chosen so it does not take Paste and Match Style, `⌥⇧⌘V`, from every app)
- **Cursor Quick Menu** — with *Open a small menu at the cursor* on (off by default), `⌘⇧V` inside a focused text field shows a compact list of the last five clips at the cursor position instead of the shelf
- **Undo and redo** — `⌘Z` takes back the last delete of clips or a collection, the last change to a clip (title, note, tags, icon, collection, pin, paste shortcut, sensitive mark, expiry, place in a collection), to the collections (create, edit, duplicate, reorder) and to snippets, and an import; `⇧⌘Z` redoes it, and the Settings window's Edit menu does the same. A bar offers Undo after a delete from the shelf, and the delete question says whether it can be undone. Clear History and Clear Everything are final. The last 20 actions are kept in memory (at most 16 MB, still encrypted) and forgotten on lock, Clear History, Clear Everything and quit; expiring clips, credentials and clips over 4 MB are not kept (ADR 0008)
- **Drag-and-drop** — drag a clip from the shelf directly into the target app
- **Paste All** — select two or more text clips and press Paste All (`⌘P`): they are joined with a blank line and pasted at once; nothing new is saved
- **Append** — once enabled in Settings → Shortcuts, double-press `⌘C` within 500 ms to append the new copy to the most recent clip
- **Paste One by One** — select several clips and press Paste One by One (`⇧⌘P`): the first pastes when the shelf closes, then each plain `⌘V` in any app pastes the next; a small panel shows where you are and has Cancel (also in the menu bar). Needs Accessibility; without it `⌘⇧V` pastes the next one.

### Intelligence
- **Masked secrets** — credit cards, API keys, JWTs, SSNs, password lines are detected and masked on the shelf; the real text shows only through Show (after Touch ID or the password; it stays until Hide, the shelf closes, the history locks or contents are covered) and is what a paste writes
- **AI actions** — summarize (a long text one part at a time, as you ask), translate and extract text, and describe pictures, all with Apple's on-device model (macOS 26+ with Apple Intelligence; describing pictures needs macOS 27). No account, no API key, nothing leaves your Mac. On a Mac without Apple Intelligence these actions are grayed out with the reason. Right-click any text or code clip and choose an action; the answer opens in a panel and is never requested automatically.

### Privacy & security
- **Encrypted at rest** — clipboard payloads, previews, titles, notes, tags and search vectors are AES-GCM-256 encrypted before they touch the SwiftData store (colors and the masked preview of a secret stay readable by design; the privacy guide lists every exception); the key is random per install, held in the login Keychain (`…ThisDeviceOnly`) and never leaves this Mac. It is not wrapped by the Secure Enclave, so it protects a copied-off database, not a logged-in attacker (see `decisions/0002-clip-data-is-sealed-at-rest.md`).
- **Encrypted backup** — one encrypted file per Mac in iCloud Drive or a folder you choose, protected by a passphrase or a recovery key, kept up to date automatically or on demand; restore any backup file. Off until set up in Settings → Data → Backup.
- **Sync (not built)** — multi-device sync is designed but not built (`SyncAvailability` is off); see `docs/sync-design.md`.
- **No analytics** — zero telemetry and crash reporters; no analytics SDK (a pre-push hook and a CI check for eleven names, and a test of the build files); Sparkle is the one bundled third-party framework
- **Privacy promise** — Settings → Privacy opens with what stays on this Mac (encryption and the key, no upload, on-device AI, what update checks do, the backup), then the lock, exclusions, how many copies were left out of history (counts only), the content filter and link previews. **Clear Everything** is in Settings → Data → Start over
- **Exclusion list** — password managers and other apps you exclude are silently skipped
- **Touch ID lock** — optionally require Touch ID to view clipboard history again a set time after each unlock, one setting, *Ask for Touch ID again after* (1, 5, 15 or 60 minutes); history is blurred until authenticated
- **Shown secrets and pasted secrets** — a secret you show stays shown until you hide it, the shelf closes, the history locks or the contents are covered. A secret you paste is kept off Universal Clipboard and out of other managers, and leaves the clipboard after 30 seconds. A password manager you allow has its copies kept hidden as Credential clips and deleted when the allowance ends, and within a day at the latest.
- **Hide Clip Contents** — blur every clip by hand from the menu bar, a Shortcuts action, an optional shortcut or a Focus filter. Hide during screen sharing (off by default) also watches for a mirrored display, known sharing apps and the sharing bar of Chromium browsers and Firefox; it cannot see a single-tab share or one from Safari.
- **Sensitive-content filtering** — links are checked on-device by address (blocklist, run-together host words) and, when link previews are on, page title; pictures, and the pictures on linked pages, are screened best-effort by your Mac's on-device model (macOS 27 with Apple Intelligence). Blur (default; the **Show** button reveals a card, and Return or a double click pastes it without showing it), hide or show. Any card can be marked sensitive by hand.

### Customization
- **Appearance** — light, dark, or system-follow + accent color (the theme's own by default, or a named color or your own); an optional second theme for dark mode; applies to the shelf and the Settings window only; app icon (Basil, Parmesan, Pine nut or Mortar, one for each theme) and four themes (each drawn in light and dark, and checked to look different from the others) that set the accent, a shelf tint and the icon together for the Dock and app switcher
- **Card size** — one slider from 160 to 240 points wide, with Small, Medium and Large ticks at 160, 200 and 240; in Settings → Appearance
- **Ask Pesto** — type a question such as "the invoice link from last week" and press Ask (sparkles): it turns the words into type and date filters plus keywords. Uses the on-device model when Apple Intelligence is on, simple built-in rules otherwise; nothing leaves the Mac.
- **Configurable hotkeys** — live-record ⌘⇧V (open the shelf) and ⌃⌥⌘V (paste as plain text), and the shortcuts for pasting the previous clip, the floating window, pausing capture and hiding clip contents (unset until you record them), via a click-to-capture recorder in Settings → Shortcuts (Pesto pauses its own shortcuts while one is recorded, Esc cancels, and a clash is refused with its reason); ⌃1–⌃9 pins are always available
- **Floating window** (the menu-bar icon can be hidden in Settings → General) — always-on-top resizable floating panel toggled from the menu bar; a click or Return on a clip pastes it into the previously focused app (turn off *Paste from the floating window* in Settings → General → Copy and paste if you prefer copy-only staging; the shelf itself pastes with Return or a double click). Position persists between sessions.
- **Settings in the backup** — the encrypted backup carries your preferences; Restore from Backup offers *Restore settings too*, and settings that would delete history or keep less of it wait for *Apply These Too*. Settings → Data → Backup.
- **Retention policy** — how long to keep clips and how many (Settings → Data → History); pinned clips are exempt
- **Expiry per clip** — from the clip menu (Set Expiry): burn after paste, or expire in 1 hour, 24 hours or 1 week
- **Automatic ingest rules** — strip URL tracking parameters, normalize line endings, trim whitespace, collapse duplicate spaces; configurable per rule in Settings → Data → Clean up copied text
- **Auto-update** — Sparkle 2.x feed; Pesto checks for updates automatically (a request to the appcast host only) and installs only with your approval

### Search and suggestions
- **Semantic search** — queries > 8 chars also match by cosine similarity (NLEmbedding, on-device, degrades gracefully when model unavailable). Semantically similar clips are appended to substring results.
- **Smart Collections** — Settings → Collections shows suggestions when it opens: on-device k-means clustering of the last 200 embedded clips gives up to five Topics, each named after its key terms and kept only when a rule on one of those terms gathers most of the cluster; each is a suggested collection you can create with one click.
- **Syntax highlighting** — code clips in the hover card are colored (14 languages: Swift, Python, JS/TS, Go, Rust, SQL, Shell, HTML, CSS, Java, Kotlin, Ruby, C/C++/ObjC).

### Automation

- **Shortcuts and Spotlight** — Open Pesto, Search Pesto, Copy from Pesto, Copy Text to Pesto and Hide Clip Contents are App Shortcuts: they appear in the Shortcuts app and, as actions, in Spotlight without setup. Pesto puts no clips into Spotlight. Hide Clip Contents is also a Focus filter.
- **Import from another app** — Paste (pinboards become collections) and ten other clipboard managers: Maccy (pinned items become a collection), Alfred (text and file paths), CleanClip, PasteNow, CopyClip, PastePal, Pastebot, Clipy, Flycut and Unclutter; plus snippets from a Raycast export (TextExpander and Alfred can convert theirs to it). Each reads a copy of the library, read-only.
- **Snippet editor** — Settings → Snippets edits in the list, with a *Fill From Mac…* menu for the tokens Pesto fills in (`{{date}}`, `{{time}}`, `{{datetime}}`, `{{isodate}}`, `{{weekday}}`, `{{date+Nd}}`, `{{clipboard}}`, `{{uuid}}`, `{{app}}`, `{{cursor}}`), an *Add Question…* menu and a *When you paste* list of the questions asked at paste time (rename, starting value, options, remove), *Suggest Names* (on-device model) and a live preview.
- **Fill-in snippets** — `{{input:…}}`, `{{choice:…}}` and `{{optional:…}}…{{/optional}}` ask for a value in a small panel when the snippet is pasted (shelf, `⌃1`–`⌃9` shortcuts, quick paste, AppleScript; a stack asks up front). Fields start with the last value typed, kept sealed with the snippet (Settings → Snippets → Remember fill-in values). Raycast `{argument}` and TextExpander `%fill…%` import as these tokens.
- **Look-alike suggestion** — the shelf offers one snippet for three or more clips that differ in a few words, over two or more days (ADR 0017); a clip pasted on three different days of the last thirty is offered a shortcut instead.
- **Start over** — Settings → Data → Start over → Clear Everything removes every clip (pinned too), collection and snippet, keeps settings, and asks whether to keep or delete the backup.
- **URL scheme (`pesto://`)** — `open`, `list`, `search?q=`, `paste?id=`, `pin?id=`, `collection?name=`, `clear?range=hour|today|all` (asks for confirmation; the range is required), `summary?id=`. Usable from Alfred workflows, Keyboard Maestro, shell scripts.
- **AppleScript** — `copy item "text"`, `get last item`, `search history with query "text"`, `paste item id "UUID"`, `list collections`, `clear history range "hour"|"today"|"all"` (asks for confirmation). Works with Automator and Script Editor.

### Insights
- **Activity dashboard** — daily copy counts, type distribution, and top source apps for the last 7 or 30 days; in Settings → Data, under Activity
