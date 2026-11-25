# Decisions

Architecture decision records: the decisions that shape Pesto and the reasons behind them. Read the one that governs
an area before changing it. Each is one page: why, what was decided, what it costs, and which docs it touches.

An accepted record is not edited once the project is public. A change of direction is a new record that says which one
it supersedes, and the old one's status line points to it. Smaller designs that are not decisions (how snippets and
suggestions work, the notch proposal) live in `docs/design/`.

| ADR | Decision |
|---|---|
| [0001](0001-free-and-open-source-no-feature-gating.md) | Pesto is free and open source, every feature ships on every install, and it installs as one copy in Applications |
| [0002](0002-clip-data-is-sealed-at-rest.md) | Clip data is sealed at rest and bound to its item, Clear Everything replaces the key, and the plaintext exceptions are listed |
| [0003](0003-secrets-are-masked-and-shown-on-request.md) | Secrets are masked and pasted without showing, one authentication window guards Show, and a cover hides the shelf while sharing |
| [0004](0004-what-is-never-captured.md) | Built-in exclusions are permanent, a timed allowance keeps hidden copies, and other devices' copies are opt-in |
| [0005](0005-no-network-but-a-short-list-and-ai-on-the-device.md) | Pesto uses the network only for a closed list, and every AI feature runs on the device |
| [0006](0006-the-capture-pipeline.md) | The watcher polls on an input-driven timer, a copy shows at once and is judged afterwards, and ingest is bounded |
| [0007](0007-storage-and-app-state.md) | Clips live in a light item and a sealed blob inside PestoCore, one observable history store feeds the shelf, and Core is a one-way graph of directories |
| [0008](0008-undo-keeps-sealed-snapshots-in-memory.md) | Undo and redo restore deletes and edits from sealed snapshots kept in memory |
| [0009](0009-the-shelf-and-paste.md) | Paste waits for the target's keyboard, a click focuses and a double click pastes, and the hover card is a window of its own |
| [0010](0010-backup.md) | The backup is one encrypted, chunk-authenticated file per Mac, kept current automatically and guarded against shrinking; sync is designed, not built |
| [0011](0011-read-only-surfaces.md) | Importers, the command-line tool and AppleScript are read-only surfaces that never open the store |
| [0012](0012-settings-and-shortcuts.md) | Settings are seven panes with search that goes to the row, typed keys with one default, and one list of global shortcuts |
| [0013](0013-appearance-and-shelf-position.md) | Four themes share one identity with the icons, a theme owns the shelf's colour, and the shelf opens at the Bottom or the Top |
| [0014](0014-shelf-suggestions.md) | Shelf suggestions offer shortcuts, free idle keys and suggest snippets without moving cards |
| [0015](0015-a-declined-suggestion-comes-back-once.md) | A declined suggestion comes back once, after the clip is used twice as much and thirty days pass |
| [0016](0016-search-arrows-move-cards.md) | In search, the arrow keys move between result cards and Return pastes; supersedes the key handling of 0009 |
| [0017](0017-smart-snippets.md) | Snippets ask for fill-in fields at paste time, and Pesto offers them for clips that differ in a few words |
| [0018](0018-multi-device-sync.md) | Macs sync through an encrypted, append-only log per Mac in a folder the person picks, with a separate sync key (iCloud Keychain once Developer ID exists, by hand until then) and one Reset Sync action |
| [0019](0019-backup-and-sync-group.md) | Settings → Data shows backup and, later, sync as two switches in one group, with one place for where the copies live; supersedes the Settings wording of 0010 and 0012 |
| [0020](0020-decode-jwt-is-a-second-way-into-a-hidden-clip.md) | Decode JWT is a second way into a hidden clip: same authentication, read-only, closes with Show |
| [0021](0021-a-collection-keeps-a-clip-where-it-was.md) | A collection keeps a clip where it was; only the history moves it on use |
| [0022](0022-data-pane-backup-and-sync-cards.md) | Settings → Data gives backup and sync a card each and drops the Backup stat tile |
| [0023](0023-time-filter-is-one-chip-and-a-custom-range.md) | The When filter is one chip with a menu, and a range can be any span Ask can read |
| [0024](0024-launch-at-login-starts-on-in-setup.md) | Setup's last step offers "Launch Pesto at login" already on, once per Mac, and keeps the person's answer |
| [0025](0025-filter-menu-chips-say-what-they-are-set-to.md) | The Format and From chips read Any and Any app at rest, then their value; supersedes a sentence of 0023 |
| [0026](0026-cards-put-the-content-first.md) | Picture, color, short text and a link's host fill their card; the decision is `CardTreatment` in Core and anything hidden or covered keeps today's card |
| [0027](0027-one-band-style-and-two-small-shelf-hints.md) | The Suggestion, Undo and import offers share one glass-capsule banner; No results names the filters on and offers Clear Filters; a click on a card hints at the double click, three times at most |
| [0028](0028-a-covered-card-shows-number-kind-and-age.md) | A covered card shows its ⌘ number, its kind as one plain word and its age, from one tested allowlist, and nothing that identifies the content or origin; keeps 0003 |
| [0029](0029-snippets-pane-leads-with-your-snippets.md) | The Snippets pane leads with your snippets, starters and clip suggestions; the placeholder reference is one closed disclosure row; the fold is superseded by 0030 |
| [0030](0030-placeholders-are-shown-in-the-snippets-pane.md) | The Snippets pane shows the placeholder reference, still after the snippet sections, with a link to the guide; supersedes the fold of 0029 |
| [0031](0031-short-text-and-link-hosts-use-two-sizes.md) | Short text and a link's host are set in two sizes, 24 and 18 pt, with the first line at one fixed distance under the header; supersedes the sizes of 0026 |
| [0032](0032-paste-import-keeps-pinboards-and-newest.md) | A Paste import keeps the pinboards and the newest history that fits the cap and the retention setting, and says so before it starts; supersedes the Paste bounds of 0011 |
| [0033](0033-paste-as-json-and-markdown.md) | Paste As and Copy As offer JSON and Markdown only for a clip that qualifies; JSON replaces JSON Pretty-Print, and a hidden, covered or oversized clip is never read |
| [0034](0034-copy-recognized-text.md) | A picture's whole recognized text (up to 100,000 bytes) is kept in its own sealed file, scanned for secrets in full, and copied from the menu or a Copy Text button on the hover card, which takes the pointer; amends the pointer rule of 0009 |
| [0035](0035-shelf-surface-solid-or-glass.md) | The shelf is solid by default and glass by choice (Settings → Appearance → Shelf surface); Reduce Transparency forces solid; the wash is soft on solid; supersedes the glass parts of 0013 |
| [0036](0036-copy-text-button-hugs-its-label.md) | The hover card's Copy Text button is as wide as its label (8 pt of wash each side, 22 pt tall); supersedes the 84 pt minimum of ADR 0034. |
| [0037](0037-copy-recognized-text-makes-a-clip.md) | Copy Recognized Text writes the text as an ordinary copy (off the write gate), so it becomes a clip of its own at the front and the picture stays where it is; supersedes the "moves to the front" sentence of ADR 0034. |
| [0038](0038-sync-folder-hardening.md) | Small sync files are read through a 1 MiB cap, a grant's key is checked before it is saved, and a deletion tombstone holds no hash of a secret. |
| [0039](0039-sync-trust-hardening.md) | Pairing is eight stretched words; a Mac keeps the group and epoch it joined; a log's signer must be its Mac; join requests expire after a day; undownloaded provider files are not read yet. |
| [0040](0040-backup-passphrase-must-be-strong.md) | A backup passphrase must be strong: twelve characters at least, no common word or run, and only a strong one is accepted. |
| [0041](0041-a-picture-fills-the-card-only-near-its-shape.md) | A picture fills the card only near the card's shape (aspect 0.8 to 1.35); anything else is shown whole over a blurred copy of itself. |
| [0042](0042-link-previews-and-other-device-copies-start-on-for-a-new-install.md) | Setup turns link previews and copies from other devices on, once, for a new install; an existing Mac keeps its answer. |
| [0043](0043-paste-import-reads-external-data.md) | A Paste import reads the payloads Core Data keeps in external files, in place and read-only, and says why a clip cannot come in |
| [0044](0044-a-card-has-no-header-one-line-of-facts-at-its-foot.md) | A card has no header: the content starts at the top and one line of facts sits at its foot (number, source icon, age and size; the app's name on focus). Supersedes the header of 0026. |
| [0045](0045-collection-files.md) | A collection is shared as a `.pesto` file that carries its pictures and whole texts (secrets never written); import from the shelf and by opening the file |
| [0046](0046-pesto-on-iphone-and-ipad.md) | Pesto runs on iPhone and iPad as one more sync device: Core is one module for both platforms, capture is always the person's act, no keyboard extension (amended by 0061) |
| [0047](0047-share-extension-sealed-inbox.md) | The iOS share extension seals what is shared to the app's public key in an app-group inbox and never holds the history key; Shortcuts never hand out a secret |
| [0048](0048-a-clips-text-can-be-edited.md) | A text, code, link or color clip's content can be edited: it stays the same clip, is sealed and judged again, keeps its curation and place, is one Undo and one sync change, and is refused when another clip holds the text |
| [0049](0049-capture-method-stays-on-the-device.md) | How a clip was made on an iPhone or iPad (pasted, a note, shared, dropped, a Shortcut) is sealed in its metadata on that device only, never synced or backed up, and leads its foot line |
| [0050](0050-the-mac-edits-a-clips-text-in-its-own-window.md) | The Mac edits a text, code, link or color clip in an Edit Text window of its own, opened from the card's menu after the shelf closes; a covered card offers nothing, a secret only while shown, and one Undo takes the edit back |
| [0051](0051-autofill-inserts-from-a-sealed-quick-insert-set.md) | AutoFill inserts a clip on iPhone and iPad from a small sealed set of pinned, snippet and recent text the app keeps ready under a key only it and its AutoFill extension hold; text insertion only, never passwords, never a secret |
| [0052](0052-the-ios-widget-shows-a-sealed-snapshot-of-recent-clips.md) | The iPhone and iPad Recent Clips widget shows Pesto cards from a small sealed snapshot of the newest clips that may leave Pesto, kept only while a widget is installed and under a key only the app and the widget hold; a tap copies in place, or opens Pesto, or opens a link, as the widget is set |
| [0053](0053-an-edit-may-give-two-clips-one-text.md) | An edit may give a clip the text another clip holds: both stay on every device (sync matches by id first, a deletion names only the id while the text lives on), a fresh copy moves the one used most recently; supersedes the refusal of 0048 and 0050 |
| [0054](0054-ios-locks-and-covers-like-the-mac.md) | iPhone and iPad lock the history with Face ID, Touch ID or the passcode on the Mac's setting and one authentication window, cover cards while the screen is captured or by hand, cover the App Switcher's picture, keep no widget snapshot or AutoFill set while the lock is on, and judge clips left pending at launch |
| [0055](0055-widgets-and-autofill-while-the-ios-lock-is-on.md) | The iOS widget says Locked while the lock is on, and one setting, off by default, lets widgets and AutoFill keep showing clips. |
| [0056](0056-sync-and-undo-corrections-after-the-ios-review.md) | A remote text edit replaces the clip's text in place and keeps what only that device knows; undo, a withdrawal and the echo guard follow ids; an iPhone holds its folder per holder and a stopped pass ends; a stale bookmark is renewed; an older Pesto can move curation between two clips with one text |
| [0057](0057-the-ios-welcome.md) | The iOS welcome: three steps shown once, link previews on only when step two appears, the lock offered off, sync offered never started, AutoFill as a one-time tip, no permission prompts. |
| [0058](0058-the-mac-features-pass-3-brings-to-ios.md) | On iOS: Decode JWT behind Show's gate in a memory-only sheet, AI actions as a submenu and a sheet (none for a secret, no chunked reading), Ask Pesto as a chip in the search, smart collections in the collection editor, a GIF kept whole in and out. |
| [0059](0059-the-mac-widget.md) | The Mac gets the Recent Clips widget only in a release signed with the app's and the extension's provisioning profiles: the same sealed snapshot as iOS in the app group, Locked while the lock is on, hidden while clip contents are covered, and a chosen clip copied, shown or opened by the app through its own write path |
| [0060](0060-a-widget-can-show-a-collection.md) | A widget can be set to one collection: the sealed snapshot carries the first 24 collections (name, symbol, color) and up to eight clips each that may leave Pesto, a plain one in its hand order and a smart one by its rules over the newest 300; the bound rises to 1.5 MB |
| [0061](0061-an-optional-keyboard-inserts-from-the-quick-insert-set.md) | An optional iOS keyboard with no letter keys inserts from the quick-insert set AutoFill reads, with Full Access only; without it, a numbers-and-punctuation pad; it never holds the history key, reads the clipboard or makes a network request. Amends the "no keyboard extension" of 0046 |
| [0062](0062-the-keyboard-is-a-small-shelf-with-chips-and-a-word-search.md) | The keyboard is a small shelf: collection chips the person chooses, a row that scrolls sideways, a search by the word typed before switching (replaced on insert), and a choice to return or stay after inserting; the quick-insert set carries the chosen collections. Amends 0051 and 0061 |
| [0063](0063-the-keyboard-searches-in-its-own-field.md) | The keyboard has a search page: letters and numbers that type only into Pesto's own search field, never into the app, above the matching clips; the word-before-the-caret search stays. Amends 0061 and 0062 |
| [0064](0064-keyboard-pictures-and-default-paste.md) | The iOS keyboard reads pictures in `QuickInsertFile` with Full Access, copies pictures on tap (`localOnly`, 120s expiry) with `"Copied, paste it"`, inserts secret-scanned recognized text via long-press + `text.viewfinder` badge, and covers during screen capture (proposed) |
| [0065](0065-lock-screen-accessory-widgets.md) | iOS Lock Screen accessory widgets (`accessoryCircular`, `accessoryRectangular`, `accessoryInline`) live in `LockScreenClipsWidget` with an off-by-default per-widget opt-in (`showsClipsOnLockScreen`), use `.widgetURL` only, and never show secrets; amends 0052 |
| [0066](0066-the-keyboard-speaks-the-persons-languages.md) | The keyboard's search page offers the layouts of the person's own keyboards (Core `SearchKeyboardLayout`, Korean composed by `HangulComposer`), with iOS's key metrics, shift and accents; results rows follow the size; the shelf gets iOS's bottom row, a round search key and settings inside the keyboard; amends 0062 and 0063 |
| [0067](0067-widget-grids-near-the-card-and-pages.md) | Widget grids keep the card's shape (medium 1×2, large 2×2, extra large 2×4 on iPad) and medium and large page with an App Intent; the page lives in the extension's own preferences and resets after a newer snapshot or ten minutes; amends 0052 and 0060 |

## Template

```
# NNNN. Title as a statement of the decision

Status: Accepted

## Context
## Decision
## Consequences
## Docs affected
```
