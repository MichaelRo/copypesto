# Smart / Dynamic Snippets: research

Input to [ADR 0017](../../decisions/0017-smart-snippets.md). Researched 2026-10-28. Competitor claims come from each
product's public documentation, linked once at the end; where a source was thin it says so.

## 1. How other tools do it

| Tool | Fill-in at expansion time | Dynamic values | Suggests snippets from usage |
|---|---|---|---|
| TextExpander | Four field kinds (single-line, multi-line, optional section, popup menu); each field has a name that prompts the person; a window opens at expansion | Date and time macros with date math, clipboard, nested snippets | Yes: watches typing, proposes after repeats, notifies, lists in a "Suggested Snippets" group; Drop means never again; app allow or deny list; can be switched off |
| Raycast | `{argument}` asks in the search bar (at most three); the placeholder is replaced by what was typed | `{clipboard}`, `{cursor}`, date, `{uuid}`, with modifiers such as `| uppercase`, `trim` | None found |
| Alfred | None found for snippets; relies on workflows | `{date +7d :long}`, `{clipboard:N}` for history items, `{cursor}`, `{snippet:keyword}` | None found |
| Espanso (open source) | Forms: `[[field]]` in a template opens a form window; text, multiline, choice and list fields; submit with a button or Ctrl+Enter | Variables fed by date, shell, script and clipboard extensions | None |
| Typinator | Form fields: text, popup, combo box, checkbox; the last entered value is the default; a value can be stored in a variable and reused elsewhere in the snippet | `{clip}` for the clipboard, scripts | None found |
| Paste | No placeholders found in its documentation; pinboards hold static clips (a review notes renaming and per-app source) | None found | None found |

What the field converges on:

- **Fill-in = a named field and a small window.** Every tool that has it asks at expansion time, names the field, offers
  a default or the last value, and has a pick-one variant (popup or choice). Optional sections are TextExpander's.
- **Dynamic values are the same short list:** date with an offset, clipboard, caret position, UUID. Pesto has all four.
- **Suggestion is rare and only TextExpander does it,** by watching keystrokes system-wide, which is exactly the
  capability Pesto's invariants refuse (nothing is read except what the person copies). Its useful lessons are the
  controls: a permanent Drop, per-app limits, a switch, and a reminder when a snippet already exists for what you typed.
- **Nobody infers a template from similar clips.** That is the open space for a clipboard manager, which sees whole
  texts and not keystrokes.

## 2. What Pesto already has

- **A snippet is a pinned clip whose text holds `{{token}}`** (`docs/design/snippets-and-suggestions.md`); no model, no
  flag, so storage, search, backup and sealing are inherited (ADR 0002).
- **`TemplateExpander`** expands `date`, `time`, `datetime`, `isodate`, `weekday`, `date+Nd`/`date-Nd`, `clipboard`,
  `uuid` and `cursor` in one pass in the paste flow (`AppDelegate.expandedPayload`), before the write. Unknown tokens
  such as `{{name}}` stay as typed, and only a snippet is expanded. The token grammar is `[a-zA-Z0-9+-]+`: no colon, no
  space, no argument.
- **`SnippetDraft.placeholders`** is the Insert Placeholder menu and the rule that text with no placeholder cannot be
  saved as a snippet.
- **`SnippetSuggester` + `SnippetStarters`** feed Settings → Snippets: text pasted from the shelf 3 or more times,
  never a secret, picture, pinned clip, or text outside 8–2,000 characters.
- **Shelf suggestion** (ADR 0014, `ShelfSuggestionPolicy.nextSnippet`): an unpinned text or code clip pasted 8 or more
  times in 14 days, with no shortcut, becomes a banner; accepting opens Settings → Snippets with the clip filled in.
  Dwell, quiet period, 24 h spacing and a decline ledger bound it.
- **`SnippetPackReader`** imports Raycast, TextExpander and Alfred exports and counts tokens it cannot fill in
  (clipboard variants, selection, custom date formats). Raycast `{argument}` lands in that count today.
- **On-device model** (`Core/AI`, ADR 0005): `AppleIntelligenceClient` with `AIAvailability`, greyed-out UI, one model
  call per click and never prefetched.
- **Paste surfaces without the shelf:** pinned `⌃1`–`⌃9` hotkeys, stacks (plain ⌘V through a monitor), the CLI,
  AppleScript. They all call the same expansion, which matters for fill-ins (section 3c).

### Review of the snippet suggestion as built

1. **It rarely fires.** The shortcut offer (6 pastes, needs a free `⌃n` slot, pins the clip on accept) is evaluated
   first and the snippet needs the clip unpinned and at 8 pastes. With a free slot the clip is offered a shortcut at
   6; accepting pins it, which removes it from snippet eligibility. A snippet suggestion appears only when all nine
   slots are taken or the shortcut offer was declined or resolved. (Read from `ShelfSuggestionPolicy`; not measured
   in use.)
2. **The offer is for text that has nothing to fill in.** A clip pasted verbatim 8 times has no variable part, so
   "make this a snippet" lands in an Add Snippet sheet that refuses to save until the person invents a placeholder
   (`SnippetDraft.needsPlaceholder`). The suggestion does the part the shortcut offer already does and skips the part a
   snippet is for.
3. **Two thresholds for one idea:** 3 pastes in Settings, 8 on the shelf. Intentional (a list the person opens versus an
   interruption), but undocumented in the ADR text for 0014 beyond the 8.
4. **The design doc is stale:** `snippets-and-suggestions.md` lists only date, time, datetime and cursor; the code also
   has isodate, weekday, date offsets, clipboard and uuid. `SnippetDraft.placeholders` is the truth.

Conclusion: the expander is solid and cheap to extend; the missing piece is a value the person supplies at paste time,
and the suggestion should point at text that varies, not text that repeats exactly.

## 3. Candidate scopes

Privacy baseline for all: no network, no clip content to any service, nothing plaintext at rest (ADR 0002), a secret,
hidden or concealed clip is never read, nothing gated (ADR 0001), no new endpoints (`NetworkGuardTests` unchanged).

### (a) Repeated-phrase detection across different clips

Find a phrase (sentence, greeting, signature, boilerplate paragraph) that occurs inside several different text clips
and offer it as a snippet.

- **Pros:** catches boilerplate the person copies from varying sources; no new syntax.
- **Cons:** needs the plaintext of every text clip to be opened and shingled, continuously or on a schedule. Phrase
  boundaries are noisy (common sentences, quoted email chains, code); precision is hard and a bad suggestion costs
  trust. Copied text is mostly not the person's own boilerplate, unlike typed text, so the signal is weaker than
  TextExpander's.
- **Effort:** Large (bounded decrypting pass on the storage actor, n-gram index in memory, ranking, tests with a
  corpus, performance budget for 5,000 clips).
- **Privacy impact:** Highest of the four. Opening every sealed blob puts the whole history in memory at once, even if
  briefly. It must stay in memory, skip secrets, hidden clips, expiring clips and a locked or covered history, and
  store only clip ids and a dismissal, never the phrase (re-derived each time). The text of a result is shown only in
  the banner or sheet after the person asks. Without a manual trigger it is also a standing background reader.

### (b) Template inference: clips that differ in a few tokens become one snippet

Two or more recent clips share a skeleton (the same text apart from a name, number, date or link); offer one snippet with
a fill-in field where they differ.

- **Pros:** fits what a clipboard manager sees and no competitor offers it; the suggestion points at text that varies,
  which is where a snippet beats a shortcut; fixes review point 2.
- **Cons:** needs fill-in fields (c) to be worth anything, since otherwise the field has nowhere to go. False positives
  on lists, logs and code lines that look alike. Field naming is hard without a model (`Field 1`, or a guess from the
  surrounding words).
- **Effort:** Large (candidate selection by length and shared-prefix/suffix, token-level diff over a bounded recent
  window, template rendering, ranking, tests). Smaller than (a) because it compares few clips, not the corpus.
- **Privacy impact:** Moderate if run on demand over a bounded window (for example the last 200 unpinned text clips,
  plain text only), or when the existing paste tally already marks a clip as repeated: only then are its neighbors
  opened. The varying values (names, numbers) are dropped from the proposed template, so the saved snippet holds less
  personal data than the clips it came from. The template is saved through `StorageService.ingest`, so it is sealed
  like any clip. Opened plaintext lives only in the run.

### (c) Fill-in fields at paste time, plus context values

`{{input:Name}}` asks for a value when the snippet is pasted; `{{app}}` and similar fill from context without asking.

- **Pros:** the feature people recognize from TextExpander, Typinator, Espanso and Raycast; useful the day it ships
  with no inference; closes the gap in imports (Raycast `{argument}`, which today is counted and left as typed); makes
  (b) possible. No model, no scanning, no new data at rest.
- **Cons:** the prompt needs the keyboard, and Pesto's paste flow is built to restore the target app's focus and wait
  for the keyboard (ADR 0009). Pinned `⌃n` hotkeys, stacks and the CLI paste without the shelf, so the prompt cannot
  live only in the shelf. Grammar grows (`:` and arguments in a token), so older builds paste `{{input:Name}}` as typed,
  which is harmless and acceptable.
- **Effort:** Medium. Core: token grammar and an `inputs(in:)` that lists fields, `expansion(of:inputs:)` that fills
  them (tests first, `Core/` rule). App: one small panel, a `SafeHostingView`, `canBecomeKey` with
  `.nonactivatingPanel` so typing works without activating Pesto, then the existing focus restoration before the paste.
  The paste task is already cancelable (`PasteTaskTracker`); the prompt must be part of that task so Escape, sleep,
  lock and a second paste cancel it.
- **Context values** (no prompt): `{{app}}` (the paste target's name, which `FocusRestoration` already captures),
  `{{url}}` is not proposed (reading a browser's tab needs Automation permission; not worth a new grant). `{{clipboard}}`
  and `{{date}}` exist.
- **Privacy impact:** Low. Typed values go to the pasteboard through the same write path and are not stored, logged or
  added to the suggestion ledger. Remembering the last value per field (Typinator does) would persist what the person
  typed: not in v1; if added, it is sealed and wiped with the history. A snippet that contains a secret stays masked.

### (d) Optional on-device model for naming or inference

Apple's on-device model names a suggested snippet, names its fields (`Customer name` instead of `Field 1`), or proposes
fields in text the person pasted into the Add Snippet sheet.

- **Pros:** better names and field labels, which are the weakest part of (b) without a model; costs nothing in network
  or keys.
- **Cons:** the model exists only on some Macs (Pesto's floor is macOS 15), so every feature must stand on rule-based
  logic alone and the model only improves it. The model's output is not deterministic, so tests assert on the prompt and
  on parsing, not on the answer.
- **Effort:** Small to Medium on top of (c) or (b): a new `AIAction`-style call, `AIAvailability` grey-out, a preview
  the person accepts.
- **Privacy impact:** Low in kind, since it stays on the device (ADR 0005, security invariant 1), but it hands clip text
  to a model: so only on a click, only for one clip or one proposed template, never a secret (the masked text rule in
  `Core/AI`), never prefetched, never in a background pass (`Core/AI/CLAUDE.md`: "nothing automatic"). Greyed out with
  `AIAvailability.message` when unavailable.

### Summary

| Scope | Value | Effort | Privacy cost | Depends on |
|---|---|---|---|---|
| (c) Fill-ins + context | High, immediate | M | Low | none |
| (b) Template inference | High, differentiating | L | Moderate (on demand) | (c) |
| (d) On-device model, click only | Medium (polish) | S–M | Low | (c) or (b) |
| (a) Repeated-phrase detection | Uncertain | L | Highest | none |

## 4. Sources

- TextExpander: [Advanced snippet elements](https://textexpander.com/help/desktop/specials.html),
  [Suggested Snippets](https://textexpander.com/learn/using/snippets/create/suggested-snippets)
- Raycast: [Dynamic Placeholders](https://manual.raycast.com/dynamic-placeholders),
  [changelog 1.66.0](https://www.raycast.com/changelog/1-66-0) (argument placeholder in snippets)
- Alfred: [Dynamic Placeholders](https://www.alfredapp.com/help/features/clipboard/dynamic-placeholders/),
  [Snippets](https://alfredapp.com/help/features/snippets/)
- Espanso: [Forms](https://espanso.org/docs/matches/forms/), [Variables](https://espanso.org/docs/matches/variables)
- Typinator: [The power of Typinator forms](https://help.typinator.ergonis.com/hc/en-us/articles/22843804128284)
- Paste: [a third-party review](https://www.podfeet.com/blog/?p=33592); Paste's own documentation was not read, so its
  absence of placeholders is unconfirmed.
