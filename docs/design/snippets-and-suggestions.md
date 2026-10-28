# Snippets, and suggestions from the history

How snippets and the collection and snippet suggestions work, and why. A snippet is a pinned clip whose text holds a
`{{placeholder}}`; there is no snippet model.

## Context
People want reusable text that fills in the date or leaves the caret in the right place at paste time. A separate
snippet model would need its own schema, migration, search, backup and encryption story, when a pinned clip already has
all of them. Collections and snippets also both need a way to start: an empty list teaches nothing, and suggestions that
do not match what the person copies are noise.

## Decision
**A snippet is a pinned clip whose text holds a `{{placeholder}}`** (`ClipboardItem.isTemplate`: pinned and the
preview contains `{{`). There is no snippet model and no flag. A badge marks it on the card, and Settings → Snippets
lists them.

- Placeholders (`TemplateExpander`): `{{date}}`, `{{time}}`, `{{datetime}}` in the person's locale, short style,
  `{{isodate}}`, `{{weekday}}`, `{{date+Nd}}`/`{{date-Nd}}`, `{{clipboard}}`, `{{uuid}}`, `{{app}}` (the paste target's name)
  and `{{cursor}}`. Unknown tokens such as `{{name}}` are left as typed.
- **Fill-ins** (ADR 0017, `FillInParser`, `SnippetField`): `{{input:Label}}` (attributes `default="…"` and `multiline`),
  `{{choice:Label options="a|b"}}` and `{{optional:Label}}…{{/optional}}` are asked in a small non-activating panel
  (`FillInPromptWindowController`) inside the paste task; a label used twice asks once; without answers (a path that cannot
  ask) the defaults are used. A value typed is inserted literally, never expanded again. The panel serves every paste path
  through `AppDelegate.expandedPayload` (shelf, `⌃N`, quick paste, AppleScript); a stack asks for all its snippets' fields
  when it starts (`AppState.expandedStackItems`). The last answers are kept as `ItemMetadata.fieldMemory` (sealed), unless a
  value looks like a secret or Settings → Snippets → Remember fill-in values is off.
- **Look-alike suggestion** (ADR 0017): each ordinary text clip of 40 to 2,000 characters gets a `TextSignature` (64-position
  MinHash of its word shingles, digits read as one mark) after its card is shown, sealed in `ItemMetadata.signature`; a
  `SimilarityIndex` in memory (banded, ~2 MB at 5,000 clips) finds clips that are at least half alike. A family of three or more
  over two or more days, with one of them just pasted from the shelf, is offered as one snippet; `TemplateInferrer` aligns
  their words and turns what differs into fields. Exact repeats get a shortcut offer (pasted on three different days of
  the last thirty, `ItemMetadata.pasteDays`), never a snippet. Signatures are not in a backup and are rebuilt after a restore. Only a snippet is expanded, so Helm, Jinja or
  Handlebars text that happens to contain double braces pastes as copied.
- Expansion happens in the paste flow before the write (`AppDelegate.expandedPayload`), through
  `AppState.writeText(_:protected:)`, so all three paste tiers (ADR 0009) see the same expanded text and a secret stays
  protected. `{{cursor}}` is removed and the caret is moved back over the text that followed it
  (`TemplateExpander.expansionWithCaret`, then left-arrow keystrokes in `PasteCoordinator.executePaste`). The move is
  skipped when the paste needed a manual step, the task was canceled, the target is no longer frontmost, or keystrokes
  cannot be posted.
- Saving and editing a snippet go through `StorageService.ingest` (`addSnippet`, `updateSnippet`), so the text is
  sealed, masked if sensitive, searchable and in every backup (ADR 0002). Text the history already holds is pinned in
  place instead of becoming a second clip. The Add Snippet sheet (`SnippetDraft`) refuses text with no placeholder,
  because it would be saved and never listed, and offers Add Question and Fill From Mac menus; questions are tinted in the text and listed in a When you paste panel (ADR 0017).
- **Snippet suggestions** (`SnippetSuggester`): `SnippetStarters` (five templates, each with a placeholder and a one-line
  blurb in Pesto's voice) and text pasted from the shelf three or more times. Never offered: a secret, a picture, a
  pinned clip, text under 8 or over 2,000 characters. At most three; a dismissed id is remembered
  (`Setting.dismissedSnippetSuggestions`).
- **Snippet files** (`SnippetPackReader`) read the JSON array of `{name, text, keyword}` that Raycast exports and that
  TextExpander and Alfred converters write, at most 5 MB, 1,000 entries and 20,000 characters per entry. Single braces
  become Pesto's. An entry with no placeholder is pinned as a plain clip and counted; a token Pesto does not fill in
  (clipboard, selection, a custom date format) is counted and left as typed; empty or oversized entries are skipped and
  counted. It is reached from the importers' menu (ADR 0011).
- **Collection suggestions** (`CollectionSuggester`, Settings → Collections) are always smart collections, so creating
  one moves no clip out of another collection. *From your clips*: Links, Code, Pictures, Colors and Files when there are
  5 (3 for colors and files), copies from other devices when there are 3, and up to three apps with at least 8 clips or
  a tenth of the history. *Topics*: the clusters from `SmartCollectionSuggestions` (up to five), offered only when a
  rule on one of the cluster's key terms still covers 60% of it and matches at least three clips; each term is tried in
  order, two topics never end on the same term, and a cluster with no name is dropped. *Starters* only while the history
  is under 30 clips. A suggestion equal to an existing collection's rule, or dismissed
  (`Setting.dismissedCollectionSuggestions`), is left out. Names stay plain because they are chips read every day;
  starter descriptions carry the voice.
- **There is no "Suggest" button.** Suggestions are computed when the pane opens. When the history gives no real topic,
  none is shown; no filler suggestions about Pesto itself.
- Collection naming (`CollectionNaming`): names are unique like folder names in Finder, so a taken name gets the lowest
  free number ("Work 2"); a new collection takes the next unused color from `CollectionPalette`, and the color row
  has an Other swatch.
- The command bar's app chips (`AppChips`) are the frontmost app, never Pesto, and the three apps copied from most in
  the last seven days. Return in search pastes; it asks Pesto only when the query reads like a sentence and finds
  nothing (`AskHeuristic`: a question mark, three or more words, or two words with an intent word). ⌘Return always asks
  while searching and, outside search, shows or hides a covered clip.

Not done: a snippet model or `isTemplate` field, expanding at tap time (the pasteboard would hold the raw template),
per-snippet keywords or abbreviation expansion, and dismissed suggestions in the backup (they live in preferences on
this Mac).

## Consequences
- Unpinning a snippet makes it an ordinary clip, and a pinned clip that happens to contain `{{` becomes a snippet.
  Both follow from the convention and are accepted.
- A snippet in the history can age out only if unpinned; being pinned, it is kept like any pinned clip.
- Tests: `TemplateExpanderTests`, `SnippetTests` (draft evaluation, starters, suggester, pack reader),
  `SnippetPreviewTests`, `SnippetStorageTests`, `CollectionSuggesterTests`, `CollectionNamingTests`,
  `CollectionPaletteTests`, `AppChipsTests`, `SuggestionTallyTests` and `AskHeuristicTests`.
