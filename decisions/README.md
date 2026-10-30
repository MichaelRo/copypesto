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
| [0020](0020-decode-jwt-is-a-second-way-into-a-hidden-clip.md) | Decode JWT is a second way into a hidden clip: same authentication, read-only, closes with Show |

## Template

```
# NNNN. Title as a statement of the decision

Status: Accepted

## Context
## Decision
## Consequences
## Docs affected
```
