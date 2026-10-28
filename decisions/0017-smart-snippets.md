# 0017. Snippets ask for fill-in fields at paste time, and Pesto offers them for clips that differ in a few words

Status: Proposed

Draft for Michael to decide. Research and the evaluation of each scope: [`docs/research/smart-snippets.md`](../docs/research/smart-snippets.md).

## Context
A snippet in Pesto is a pinned clip whose text holds `{{token}}` (`docs/design/snippets-and-suggestions.md`), expanded
by `TemplateExpander` in the paste flow. Every token is filled from the clock, the clipboard or the caret; there is no
way to supply a value at paste time, so a snippet cannot say "Hi {{name}}". TextExpander, Typinator, Espanso and
Raycast all ask. Pesto's importer already meets Raycast's `{argument}` and can only count it and leave it as typed.

The snippet suggestion of ADR 0014 offers text pasted 8 times, but that text repeats exactly and so has nothing to fill
in; the Add Snippet sheet then refuses it until the person adds a placeholder. A free shortcut slot offers the same
clip a shortcut at 6 pastes first and pins it, which ends snippet eligibility. Both numbers (6 and 8) are bare counts
with no recorded reasoning and no measurement behind them. A snippet's value is in text that varies, which Pesto can see
(whole clips) and keystroke-watching tools cannot.

Constraints for every option: no network and no clip content to any AI service (ADR 0005, security invariant 1); clip
text is sealed at rest and never written in the clear (ADR 0002); a secret, hidden or concealed clip is never read for
this; nothing is gated (ADR 0001); the model does nothing automatic; and performance is a feature (the budgets in
`AGENTS.md`: copy to card under 200 ms, watcher under 0.5% CPU, memory under 150 MB).

## Options

**1. Fill-in fields only.** The syntax, the prompt, remembered values and `{{app}}`. The suggestion is fixed to hand
the Add Snippet sheet something useful.
- Gains: the recognized feature, Raycast and TextExpander imports become real, no scanning.
- Costs: the person writes every snippet by hand; the suggestion stays weak.

**2. Fill-ins plus inference on request.** Option 1, and "Find snippets in your history" (Settings → Snippets) that
compares a bounded window of recent text clips when asked.
- Gains: the differentiating feature at a bounded, visible privacy cost; nothing runs unless asked.
- Costs: the person has to know to ask; it is not the "it noticed" moment.

**3. Fill-ins, inference, and noticing as you copy (recommended, behind a performance gate).** Option 2, plus a small
similarity signature computed for each eligible text clip at ingest, so the shelf can say "these 3 clips look alike"
at the moment one is pasted, with no scan and nothing asked. Shipped as one release. The noticing part ships only if the
measurements below hold; if they do not, the release is option 2 and nothing else in this record changes.
- Gains: the moment people remember; no competitor does it from clips.
- Costs: new derived data per clip (sealed), a migration, work on the ingest path, and a precision bar: a wrong
  "look alike" costs more trust than a missed one saves. Copied text is mostly not the person's own boilerplate, so the
  suggestion will be rarer than TextExpander's; the value is quality, not frequency.

## Decision (proposed)
Option 3, built as one plan and released together, in this build order (each step lands green; the order is
dependency, not release scope):

1. **Fill-in syntax and expansion (Core, tests first).**
   - `{{input:Label}}` asks for one line. Attributes follow the label, values in double quotes, so a default may hold
     any character: `{{input:Customer default="Acme" multiline}}`.
   - `{{choice:Greeting options="Hi|Hello|Dear"}}` offers a pick; the first is the default.
   - `{{optional:Label}}text{{/optional}}` is a checkbox that includes or drops the text (off by default).
   - The same label twice asks once. `{{app}}` is the name of the app being pasted into (already captured by
     `FocusRestoration`), with no prompt. Existing tokens are unchanged; an unknown token still pastes as typed, and only
     a snippet is expanded.
   - The tokenizer moves from the single character-class regex to a small parser (labels have spaces; attributes are
     quoted). `inputs(in:)` lists the fields; `expansion(of:inputs:)` fills them. No AppKit in Core.
   - Imports convert instead of counting: Raycast `{argument name="x" options="a, b"}` and TextExpander `%filltext`,
     `%fillpopup`, `%fillpart` become the tokens above. Nothing in Pesto's syntax is chosen for Raycast parity.
   - The Add Snippet sheet's Insert Placeholder menu gains "Ask for…" items that open a small field editor and write the
     token, so nobody has to type attributes.
2. **The prompt.** One small panel, a `SafeHostingView` in a `.nonactivatingPanel` that can become key so typing works
   without activating Pesto: one row per field, the snippet name on top, Tab between fields, Return pastes (⌘Return in a
   multi-line field), Escape cancels. It belongs to the paste task (`runPasteTask`), so Escape, sleep, lock and a newer
   paste cancel it, and focus returns to the target through the existing wait (ADR 0009). It serves every paste surface,
   including the pinned `⌃n` hotkeys that never show the shelf. A stack asks for all of its snippets' fields up front,
   when the stack starts, so a plain ⌘V never waits for a person.
3. **Remembered values.** A field starts with the value last typed for it (Typinator does this), stored sealed as
   metadata of the snippet's own clip (ADR 0002), so it is wiped by Clear History, Clear Everything and deleting the
   snippet, and nothing new sits beside the clip. A value that `SensitiveContentDetector` flags is never remembered. A
   switch in Settings turns remembering off and erases what is stored.
4. **Similarity signatures.** For a text or code clip of 40 to 2,000 characters that is not secret, hidden, concealed,
   credential, expiring or from another device's excluded app, a MinHash signature of its word shingles (about 256
   bytes) is computed on the storage actor *after* the card has been shown (ADR 0006), from text the pipeline already
   holds for the content hash. Signatures are sealed with the item's id and field as associated data, kept out of the
   backup (rebuilt after a restore), loaded into an in-memory LSH index (about 1.3 MB at 5,000 clips), wiped with the
   history, and replaced with the key. Clips already in the history are indexed by a backfill that runs only in the idle
   tier, a few at a time, never on battery saver, and resumable. No signature, text or phrase leaves the Mac or is used
   by the model.
5. **The suggestion, united.** One banner, one ladder, decided by what the clip *is* (`ShelfSuggestionPolicy`):
   - The clip has near-twins (a family of three or more, at least two different days): **snippet** with a proposed
     template. Accepting opens the proposal with the differing words already turned into fields and offers a
     shortcut for the new snippet if a slot is free.
   - The clip repeats exactly: **shortcut**, as today. A snippet is never offered for text with nothing to fill in,
     unless it holds a literal date, which becomes `{{date}}` or `{{isodate}}` in the proposal.
   - Once a clip is a snippet it can be offered a shortcut like any pinned clip.
   - **Thresholds are habits, not bursts.** Replace "6 pastes in 14 days" and "8 pastes in 14 days" with "pasted on
     at least 3 different days in the last 30", which needs a short per-clip record of paste days. Where that record
     lives (sealed metadata of the clip, or the existing runtime tally) is settled when building and needs a check of
     what the storage actor can write cheaply. All numbers stay in `ShelfSuggestionPolicy.Thresholds`.
   - Presentation rules of 0014 stay: no focus, no moved cards, "this clip", dwell, quiet period, 24 h spacing, decline
     ledger.
6. **Naming from the on-device model, on a click.** In the proposal, "Suggest Names" asks Apple's model for a title and
   field labels for that one proposal (`AIActionCoordinator`); greyed out with `AIAvailability.message`; never a secret;
   never automatic. Without the model, labels are rule-based (the word before the value).

### The performance gate for step 4 and the suggestion that depends on it
Measured on a developer Mac with the existing suites (`CopyLatencyPerformanceTests`, `IngestPipelinePerformanceTests`,
`WatcherPerformanceTests`, `HistoryMemoryTests`, `LargeHistoryPerformanceTests`) plus a new one for the signature and
the lookup, and on `make bench-latency`. Ship the noticing only if all hold; otherwise ship option 2.
- Copy → card unchanged within the existing test noise; the signature work happens after the card.
- Watcher CPU under 0.5% average; the backfill adds no visible CPU while the Mac is in use.
- Memory steady state: the index adds under 3 MB at 5,000 clips.
- Lookup for one pasted clip under 4 ms, the search keystroke budget.
- Precision: on a hand-labelled set of real clip families, no family is proposed that a person would call unrelated;
  recall is secondary.

Not done: reading keystrokes, a snippet model or abbreviation expansion, `{{url}}` and `{{selection}}` (each needs a new
permission), phrase detection across unrelated clips (weak signal, highest cost), and fill-in values from the network.

## Privacy and gating checks
- Network: none added. No AI service sees clip content; the model is on the device and only on a click (ADR 0005).
- At rest: signatures and remembered values are sealed and bound to their item (ADR 0002). A signature of a clip that
  has none of the eligibility is never computed. This needs an addition to ADR 0002's list of sealed fields, which this
  record makes (it extends the list; it changes no existing line).
- Secrets: never indexed, never read for inference, never fed to the model, never remembered, never shown in the prompt.
  A snippet that holds a secret stays masked and is written protected (`AppState.writeText(_:protected:)`).
- Covered or locked: the suggestion and prompt follow the existing suppression (history locked, content covered).
- Analytics: none. Nothing is counted or reported.
- Gating: none. Every part ships to every install (ADR 0001); the model step greys out where the model is missing.

## Consequences
- The token grammar grows. A build older than this one pastes the new tokens as typed; backups stay readable.
- A paste can wait for a person. The panel is a new surface in the paste flow and the highest-risk part: focus
  restoration, cancellation and the manual-paste toast need tests and a hand check on hardware.
- The ingest path gains work after the card and a new sealed column (a SwiftData migration; the backup omits it).
- This record supersedes ADR 0014's snippet moment (its trigger and what accepting does) and its 6 and 8 thresholds;
  the rest of 0014 stands. 0014's status line points here once this is accepted.
- `SnippetSuggester`'s Settings list (3 pastes) is replaced by the same family and day rules.

## Docs affected
- `README.md` (Features: fill-in snippets, finding snippets)
- `ROADMAP.md` (Smart / Dynamic Snippets moves from Next to shipped)
- `docs/guide/using-pesto.md`, `docs/guide/settings.md` (snippets, remembered values switch), `docs/guide/shortcuts.md`
- `docs/guide/privacy-and-security.md` (what is indexed and sealed, what inference reads)
- `docs/design/snippets-and-suggestions.md` (placeholder list, already behind the code, and the new tokens)
- `decisions/0002-clip-data-is-sealed-at-rest.md` is not edited; this record adds the sealed fields
- `decisions/0014-shelf-suggestions.md` status line
- `Sources/Core/Paste/CLAUDE.md` (the prompt in the paste task), `Sources/Core/AI/CLAUDE.md` (naming, click only)
