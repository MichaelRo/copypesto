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
| [0018](0018-multi-device-sync.md) | Macs sync through an encrypted, append-only log per Mac in a folder the person picks, with a separate sync key (iCloud Keychain once Developer ID exists, by hand until then) and one Reset Sync action (proposed) |
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
| [0038](0038-sync-folder-hardening.md) | Small sync files are read through a 1 MiB cap, a grant's key is checked before it is saved, and a deletion tombstone holds no hash of a secret. |

## Template

```
# NNNN. Title as a statement of the decision

Status: Accepted

## Context
## Decision
## Consequences
## Docs affected
```
