# AI on long documents: read a long text one part at a time, and let the person decide how far to go

**Implemented 2026-10-21** (`AIChunker`, `AIRun`, `AppState+AIParts`, `AIPartsView`; hosted `AIPartsFlowTests`, `AIPartsUITests` with a fake model). One
simplification: Paste and Copy give the part summaries one after another without their labels (or the combined summary once
there is one). Decided 2026-10-21 (the owner delegated the choices, with Pesto's CPU and memory use ahead of
polish): see "Decisions" at the end.

## What is true today
- A text action sends the clip's whole text up to a budget (`AIInput.make`, `AIInputBudget`): `(contextSize - 1200) * 3`
  characters, clamped to 4,000...40,000, so about 8,700 characters on today's model. The text is cut at the last
  whitespace inside the budget and the answer says "Based on the first N of M characters." (`AIResult.Coverage`).
- `GridView+Actions.aiSource` hands the whole text of an ordinary clip (`ClipText.full`), the masked preview of a secret,
  and the 500-character preview of a clip too big to decrypt on the main thread.
- One request, one answer, one panel (`AIResultPanelController`): Paste (Return), Copy Result, Done. Nothing runs in the
  background (ADR 0005), and every AI surface greys out with `AIAvailability.message` when the model is unavailable.

## Skeptical reading of the item
"Chunked summary" can mean three things, and only one of them is what the backlog item asks for.
1. **Map-reduce on its own** (summarize every chunk, then summarize the summaries, unasked): rejected by the item itself.
   A 60,000-character text is 7 model calls the person never asked for, on a model that is on their Mac and takes seconds
   per call, with no way to say "that is enough".
2. **A bigger budget:** already at its ceiling of 40,000 characters, and the real limit is the model's 4,096-token
   window, not our clamp. More characters per call is not available.
3. **Parts the person steps through** (the item): the first part is summarized at once; the panel then says what is
   left and asks. Each click is one call. This is the design.

Not every action fits. **Summarize and Key Points** are about the content, so a part's answer is useful by itself.
**Professional, Concise and Translate** rewrite the text: their answer is as long as their input, a second part cannot
be stitched to the first without the model seeing both, and "read the next part?" would hand back a document in pieces.
**Extract** lists entities and could be merged later, but nothing asks for it. So: **chunking is for Summarize and Key
Points only**; the other actions keep today's cut text and its "Based on the first N of M characters" note.

## Proposal
### Parts
- `AIChunker.parts(of:budget:)` in Core, beside `AIInput.make` (which stays the only place text is cut). It returns the
  ranges of the text, each at most `budget` characters, cut at the best boundary inside the budget: a blank line, then the
  end of a sentence (`. `, `? `, `! `, a line end), then whitespace, then the budget itself for one very long word. The
  parts cover the text in order with nothing lost but the whitespace at the cuts.
- A ceiling of **12 parts** (about 100,000 characters at today's budget). Past it the last part's note says so ("The first
  12 parts of 21 were available"), as the cut text does today. The model is not asked to read a book.
- A secret never chunks: a masked clip stays a single masked request, as today.

### Answers
- **Parts are summarized independently and stay on screen**, each under its range: "Part 1 · characters 1-8,640". The
  alternative, a rolling summary that is rewritten with each part, reads better but replaces text the person has already
  read, can drop what the first part said and compounds a mistake. Independent parts are transparent, a failed part loses
  nothing before it, and nothing needs the earlier answers as input (so the budget per part is the whole budget).
- When the last part is done the panel offers **Combine** (one more call over the part summaries, which are short enough
  to fit): the person asks for it, it is never automatic.
- **Paste and Copy Result act on what is on screen**: the parts so far, joined by a blank line, labels included only
  when there is more than one part. A secret is protected as today (`isProtected`).

### The panel
```
 Summarize                                              [clip preview, 1 line]
 Part 1 of 5 · characters 1-8,640 of 41,205
 ───────────────────────────────────────────────
 <summary of part 1>
 Part 2 of 5 · characters 8,641-17,300
 <summary of part 2>
 ───────────────────────────────────────────────
 Read the next part?          [ Read Part 3 ]   (spinner and Cancel while it runs)
 [ Paste ↩ ]  [ Copy Result ]                                          [ Done ]
```
- The question line replaces "Based on the first N of M characters" when a part is waiting; with no part left it says
  "Read all 5 parts." and offers Combine.
- **One call per click, never ahead of the click.** Reading the next part in the background to hide the latency is the
  obvious optimization and is ruled out: ADR 0005 forbids automatic AI requests and the person may not want the cost.
- Return stays Paste (the panel's default action, `docs/design/ai-result-paste.md`). Read Next Part is a normal button
  reachable by Tab, with `⌘]` proposed as its shortcut (to be hand-checked against the panel's key handling).
- A failure of part N shows the error under part N with **Try Again**, and keeps parts 1 to N-1. Closing the panel ends
  the run; the remaining text is not kept.
- Reduce Motion: new parts appear without animation (`Motion.animation`). VoiceOver: each finished part is announced
  ("Part 2 of 5 summarized", `AIResultAnnouncement`), and the button's label says how many parts remain.

### Where the code goes (when it is built)
- Core: `AIChunker` (pure, tested), `AIRun` (value: the parts, the next index, the answers so far), and
  `AIActionCoordinator.runNextPart(_:)` taking the same injected `complete` closure, so a test counts the calls.
- `AppState`: `aiResult` stays a single `AIResult`; a new `aiRun: AIRun?` holds the rest of the text in memory only while
  the panel is open and is cleared when it closes. **Check before building:** whether locking the history closes the AI
  panel. If it does not, it must, because a run keeps the rest of a document in plaintext in memory.
- The panel view gets the part list, the question row and the button; strings with a count ("Part %1$lld of %2$lld") need
  plural catalog entries that print both numbers.
- Docs: `docs/guide` AI page, `docs/feature-reference.md`, and the stale line in `ai-result-paste.md` (fixed with this
  note). ADR 0005 says text actions cut at 8,000 characters; that has been `AIInputBudget` since the budget was measured.
  It is an accepted ADR, so it is reported here and not edited; the implementation's ADR note is where it is corrected.

### Tests the implementation needs (written first)
- `AIChunkerTests`: no part over the budget; the parts in order cover the text; each boundary kind is preferred in turn
  (blank line over sentence over whitespace over a hard cut); one very long word; text under the budget is one part;
  the 12-part ceiling and its note; whitespace-only and empty text; Unicode (emoji, combining marks) never split inside a
  character; an adversarial 5 MB text chunks in well under a frame.
- Coordinator tests with a recording `complete`: one call per `runNextPart`, the prompt holds only that part, a failure
  keeps the earlier answers and a retry asks for the same part, a masked clip makes one call.
- Hosted: the panel's state through a run (waiting, running, failed, finished), Cancel, and Paste joining what is shown;
  a UI test for the button and the announcement.

## Alternatives rejected
- Automatic map-reduce, rolling summaries and background prefetch (above).
- Chunking the rewrite actions: their output is a document, not a summary.
- A progress bar over all parts: it suggests the person must finish them.
- Choosing the part size in Settings: the budget comes from the model; a second knob would only break it.

## Decisions (2026-10-21)
1. **Independent parts that stay on screen.** Chosen for cost, not looks: each click is one call with only that part as input, so
   nothing grows with the number of parts (a rolling summary re-reads and rewrites what is already known, and a failure
   or a cancel loses the lot).
2. **Summarize and Key Points both chunk.** It is the same machinery and costs nothing extra; the rewrite actions keep
   today's cut text.
3. **The ceiling is 100,000 characters read, not a number of parts**, so a model with a larger window does not multiply the
   work. At today's budget that is about 12 parts. The text for those parts (about 0.4 MB) is kept in memory only while the
   panel is open and is dropped when it closes or the history locks; a 5 MB clip is never held whole. Each call runs on the
   on-device model only when its button is pressed, never ahead of the click, and Cancel cancels the task.
4. **No shortcut.** It is an edge case; the button is reachable by Tab.
