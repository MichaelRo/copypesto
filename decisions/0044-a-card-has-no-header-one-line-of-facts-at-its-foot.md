# 0044. A card has no header: the content starts at the top and one line of facts sits at its foot

Status: Accepted

Supersedes the header of ADR 0026 ("the header stays the quiet band for every card that keeps one", and the header that floats over a picture or a color on a scrim). ADR 0026's treatments (a picture or a color fills the card, short text and a link's host are set large), ADR 0031's sizes, ADR 0041's picture fit and ADR 0028's covered card are unchanged. Nothing about storage, encryption, sync or the network changes.

(0043 is taken by a record on another branch, so this one is 0044.)

## Context
Every card spent two rows on facts about the clip: a 34 pt header (app tile, the app's name or the kind word, the age) and a footer (shortcut number, a size, badges). On the Small card that was 76 of 140 points. On a picture the header needed a scrim at 90% of the surface colour to keep its text readable, which in dark appearance put a dark smear over the top of every light screenshot.

Five directions were drawn on the real shelf with a seed that looks like a real clipboard (white screenshots, long links, chat, code, a secret), in light and dark, two themes and two sizes: no header band, no header at all, ruled columns without card fills, today's card with a theme-only wash, and a shelf with deeper shadows and focus by scale. Only "no header at all" changed how the row reads: the eye lands on the clips. The owner chose it on 2026-11-12, and asked that nothing the header and footer said be lost by accident.

## Decision
- **No header on any card.** The content starts `CardLayout.contentTopInset` (10 pt, the side margin) under the card's top edge. Text cards show 6, 7 and 8 lines at the three sizes, where they showed 4, 5 and 6.
- **One line of facts at the foot** (`metaLine`, `ClipboardCard+MetaLine.swift`), the same grammar on every card: the ⌘ number; the source tile at 16 pt (the app's icon, the clip's own symbol, or the other-device tile); then text; then, at the trailing edge, what the person did to the clip (expiry, snippet braces, the ⌃ shortcut or its suggestion, the pin, the collection, the secret's category).
- **What the text says is a tested rule in Core** (`CardMetaLine`). At rest: the age and the clip's size ("4m ago · 149 characters · 5 lines"). On the focused or pointed card the app's name leads ("Xcode · 4m ago"). A title the person gave always leads and is the last thing given up. The view shows the fullest wording that fits and gives up the lines, then the size, then the collection's name (its icon stays), then the text.
- **A size is stated only when it tells something.** A short text set large is the whole clip, so its card does not count it (`CardTreatment.showsWholeClip`). A color's value is the large label on its card, and a picture's byte size was never on a picture card; both stay as they were.
- **16 pt for the source tile.** Every Mac app icon carries a drawing made for 16 pt (32 px at 2x), so it is sharp where 14 pt is a resample; it is the height of the keycap beside it; and it is the size the Finder's list view, the menu bar and a favicon use for "which app" at a glance.
- **On a picture there is no scrim.** Everything in the line sits on the pill ground (`PictureScrim.pillOpacity`, 85% of the surface colour), which is the ground ADR 0026 already proved at 4.5:1 over the worst picture (`PictureScrimTests`). On a color the line is the fill's own ink (`CardInk`).
- **Cut on purpose, to keep the line to what a person acts on:** the paste count (the hover card says "Pasted 4 times", and VoiceOver reads the same facts); the pin beside a snippet's braces or a ⌃ shortcut, which only a pinned clip has (`CardMetaLine.showsPin`); the kind word ("Link", "File", "Image", a code clip's language) and the app's name at rest. The content shows the kind, the icon shows the app, and VoiceOver's label and value still say both (`CardAccessibility`, unchanged). The source app's colour wash went with the band.
- **Motion:** the card's lift, focus ring and selection use `pestoMove`, `pestoQuick` and `pestoQuick`. `MotionFamilyTests` fails on a curve of its own handed to `Motion.animation`, with a list of the files that still have one, which may only shrink.

## Consequences
- The row reads as clips, and a card has one quiet line instead of two bars. A person who scanned by the app's name now scans by its icon; the name is one arrow press or a hover away.
- A covered card (ADR 0028) is unchanged and still shows no app.
- The line can be crowded on a pinned snippet with a shortcut inside a collection on the Small card; it degrades in the order above and never truncates a word mid-way. On a collection's own shelf the cards do not repeat that collection's badge, which is what leaves room for a snippet's title there.
- `LightCard` has no band. `PictureScrim` keeps the constants the link-picture body and the pills use; its header curve is gone.
- Every picture of the shelf, the website's shelf and the film's frames are retaken (`make pictures`, `make teaser`); `docs/design/website-shelf-spec.md` says which of its sections are out of date until then.
- To be measured before merge: `make bench-shelf` (view bodies and commit time per arrow press; the line is one `ViewThatFits` of at most six rows where the footer had three), `make bench-scroll`.

## Docs affected
- `docs/design/website-shelf-spec.md` (values table and a note; the treatments table follows with the new pictures)
- `docs/design/card-typography.md` (its header is history)
- `README.md`, `docs/guide/using-pesto.md` (pictures and any sentence that names the card's header)
- `AGENTS.md` (the motion line names `MotionFamilyTests`)
- `decisions/README.md` (this record in the table)
