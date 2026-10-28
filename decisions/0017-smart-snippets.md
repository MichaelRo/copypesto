# 0017. Snippets ask for fill-in fields at paste time first; inference from similar clips follows, on request

Status: Proposed

Draft for Michael to decide. Research and the evaluation of each scope: [`docs/research/smart-snippets.md`](../docs/research/smart-snippets.md).

## Context
A snippet in Pesto is a pinned clip whose text holds `{{token}}` (`docs/design/snippets-and-suggestions.md`), expanded
by `TemplateExpander` in the paste flow. Every token is filled from the clock, the clipboard or the caret; there is no
way to supply a value at paste time, so a snippet cannot say "Hi {{name}}". TextExpander, Typinator, Espanso and
Raycast all ask. Pesto's importer already meets Raycast's `{argument}` and can only count it and leave it as typed.

The snippet suggestion of ADR 0014 offers text pasted 8 times, but that text repeats exactly and so has nothing to fill
in; the Add Snippet sheet then refuses it until the person adds a placeholder, and a free shortcut slot offers the
same clip a shortcut at 6 pastes first and pins it, which ends snippet eligibility. The value of a snippet is in text
that varies, which Pesto can see (whole clips) and keystroke-watching tools cannot.

Constraints that hold for every option: no network and no clip content to any AI service (ADR 0005, security invariant
1); clip text is sealed at rest and never written in the clear (ADR 0002); a secret, hidden or concealed clip is never
read for this; nothing is gated (ADR 0001); nothing automatic from the model.

## Options

**1. Fill-in fields only.** `{{input:Name}}` (and a pick-one variant), asked in a small panel at paste time, plus
context values such as `{{app}}`. Fix the snippet suggestion to hand the Add Snippet sheet something useful.
- Gains: the recognized feature, imports of Raycast arguments become real, no scanning, no new data.
- Costs: the person writes every snippet by hand; the suggestion stays weak.

**2. Fill-ins, then template inference on request (recommended).** Option 1 first. Then "Find snippets in your
history" in Settings → Snippets and the shelf suggestion compare a bounded window of recent plain-text clips (and a
clip the paste tally already marks as repeated, with its near-twins), find clips that share a skeleton and differ in a
few tokens, and propose one template with `{{input:…}}` where they differ. The Apple on-device model may suggest field
names, only on a click and greyed out when unavailable; rule-based names (`Field 1`, or the word before the value)
are the floor.
- Gains: the differentiating feature, bounded privacy cost, each stage ships alone.
- Costs: a second large piece of work; false positives to tune; field names are plain without the model.

**3. Continuous phrase and template detection.** Option 2 plus background detection of repeated phrases across all text
clips, as TextExpander does for typing.
- Gains: suggestions without being asked.
- Costs: opens every sealed text clip in memory on a schedule; the weakest signal (copied text is mostly not the
  person's own boilerplate); highest false-positive cost; a standing reader that every future privacy review has to
  re-justify.

## Decision (proposed)
Option 2, in three stages that can each be merged and released alone.

1. **Fill-ins and context values.**
   - Grammar: `{{input:Label}}`, `{{input:Label|default}}`, `{{choice:Label|a|b|c}}`, and `{{app}}`. The same label
     twice asks once. Unknown tokens still paste as typed, and only a snippet is expanded.
   - `TemplateExpander` (Core, tests first) gains `inputs(in:)` and a fill-taking expansion; no AppKit.
   - The prompt is one small panel, a `SafeHostingView` in a `.nonactivatingPanel` that can become key so typing works
     without activating Pesto. It belongs to the paste task (`runPasteTask`), so Escape, sleep, lock and a newer paste
     cancel it; focus is restored to the target as today (ADR 0009) after Return. It serves every paste surface,
     including the pinned `⌃n` hotkeys that never show the shelf. In a stack, a fill-in snippet is asked for when it
     is readied (details open).
   - Typed values are not stored, logged or remembered between pastes in v1.
2. **Inference on request.** A Core `TemplateInferrer` over plain-text clips in a bounded window, run on the storage
   actor when the person asks or when a pasted-8-times clip is about to be suggested. Secret, hidden, concealed,
   credential, expiring and over-long clips are skipped; nothing runs while the history is locked or covered. It
   returns proposals in memory; only an accepted proposal is saved, through `StorageService.ingest`, and the varying
   values are not part of it. The ledger keeps clip ids, never text. The shelf suggestion changes from "this clip
   repeats" to "these clips look alike", and a clip that is already offered a shortcut is not also offered a snippet.
3. **Names from the on-device model, optional.** A click in the proposal sheet asks Apple's model for a title and field
   labels for that one proposal, through `AIActionCoordinator`; greyed out with `AIAvailability.message`; the secret
   rule of `AIInput` applies.

Not done: continuous or scheduled detection (option 3), reading keystrokes, a snippet model or abbreviation expansion
(unchanged from the design doc), remembered field values, `{{url}}`/`{{selection}}` (each needs a new permission).

## Privacy and gating checks
- Network: none added. No AI service sees clip content. The model is on the device and only on a click (ADR 0005).
- At rest: nothing new is stored in the clear. A snippet made from a proposal is an ordinary sealed clip (ADR 0002); the
  ledger and dismissal list hold ids only. Plaintext opened for inference lives in memory for the run, never on disk
  and never in the backup, `last-item.json` or Spotlight.
- Secrets: never read for inference, never fed to the model, never shown in the prompt. A snippet that holds a secret
  stays masked on its card and is written protected (`AppState.writeText(_:protected:)`).
- Analytics: none. Nothing is counted or reported.
- Gating: none. Every stage ships to every install (ADR 0001); the on-device model stage greys out where the model is
  missing and the rule-based result still works.
- Test budgets: inference over 5,000 clips must fit the shelf's budgets, because it runs off the main actor on request
  (measure before release; add to `docs/perf/`).

## Consequences
- The token grammar grows (`:` and `|` inside a token). A build older than this one pastes the new tokens as typed;
  backups stay readable.
- A paste can now wait for a person. The panel is a new surface in the paste flow and the highest-risk part: focus
  restoration, cancellation and the manual-paste toast need tests and a hand check on hardware.
- `SnippetPackReader` can turn Raycast `{argument}` into `{{input:…}}` instead of counting it as unfilled.
- The ADR 0014 snippet suggestion changes meaning; this record supersedes only that suggestion's trigger, not the rest
  of 0014 (the shortcut moments and the presentation rules stay).

## Docs affected
- `README.md` (Features: fill-in snippets, finding snippets)
- `ROADMAP.md` (Smart / Dynamic Snippets moves from Next to shipped, by stage)
- `docs/guide/using-pesto.md`, `docs/guide/settings.md`
- `docs/guide/privacy-and-security.md` (what inference reads, and that it stays on the Mac)
- `docs/design/snippets-and-suggestions.md` (placeholder list, which is already behind the code, and the new tokens)
- `decisions/0014-shelf-suggestions.md` status line, to point here for the snippet suggestion
- `Sources/Core/Paste/CLAUDE.md` (the prompt in the paste task) and `Sources/Core/AI/CLAUDE.md` (naming, click only)
