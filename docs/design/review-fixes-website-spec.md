# Website hand-off (2026-10-22): shelf and card changes from the accessibility and design review

## Brief for the website agent (paste this first)
> You are working in the the website repository repository. Nothing in it was edited from the app repository; this file is the
> whole spec. The app changed in six small ways that the site's sample shelf, screenshots or keyboard text may show. For
> each section below, check the site and change only what it contradicts. Do not invent features: say only what this
> file says. Never claim sync, an iPhone app, the Mac App Store or cloud AI. UI text is American English; menu items and
> buttons are Title Case, labels and captions sentence case. Attach before and after screenshots, light and dark, next to
> the app pictures named in "Reference pictures".

## 1. A card covered for sharing shows no color (D-02)
- App: the "Hidden for sharing" cover is drawn on a flat neutral ground (`Color.opaqueSurface`) under the material, so
  the clip's own tint (an image's or a color's dominant color) no longer shows through. A covered card is the card's
  rounded rectangle in a neutral dark or light fill, the eye-slash symbol, "Hidden for sharing" and a **Show** link; nothing
  of the clip, its header tint or its footer is visible.
- Site: if `Shelf.astro` or a screenshot draws a covered card, draw it the same: no tint, no header color.
- Reference picture: `Tests/PestoSnapshotTests/__Snapshots__/ClipboardCardTests/test_coveredColorCard_showsNoColor.covered.png`.

## 2. The locked shelf hides what is behind the lock (D-01)
- App: while the history is locked the shelf behind the lock screen is blurred with a radius of 30 points (it was 10) and
  covered by a flat 50% layer, so a picture's shape and a chip's name ("Notes") can no longer be read.
- Site: any picture of the locked shelf shows an unreadable, smeared shelf behind "History locked", never legible chip
  names or card contents.

## 3. Undo banner and delete question (A-09)
- App: the **Undo** link in the banner is now a small filled capsule in the accent (label color from the accent's own
  label rule); **Delete** in the "Delete these clips?" question is a solid red capsule with a white label. Cancel is
  unchanged.
- The Undo banner is a slim solid bar (28 pt) that sits in the gap under the toolbar and does not cover the clips' headers; showing it does not move the toolbar or the clips.
- Site: pictures of either show those two buttons filled, not as text links or tinted pills.

## 4. The AI result panel (A-08, D-05)
- App: the panel's height follows its answer (measured from the text, at least 90 pt for the answer, scrolling past 340 pt); its source quote is
  the quiet text color at 70% (it was the system tertiary); **Close** is a 28 pt circle with a bold symbol; **Paste**,
  **Copy Result** and **Done** are one capsule family (Paste primary, the others secondary); an error is in the status
  red.
- Site: only if a picture shows the panel.

## 5. Targets are at least 24 points (A-10)
- App: the toolbar's Search, New collection and Settings glyphs, the search field's clear button, the Show or Hide eye on
  a hidden clip, the Undo banner's dismiss button and the **Show** link on a covered card are all 24 × 24 points to hit
  (the AI panel's Close is 28). The shelf's toolbar row is therefore 8 points taller around the glyphs.
- Site: the sample shelf's toolbar buttons should be at least `1.5rem` square.

## 6. Keys on the shelf (A-02 to A-04, A-06)
Update the keyboard text of the site to the app's `docs/guide/shortcuts.md`, "On the shelf":
- **Tab** and **⇧Tab** in search walk the filter chips (**Return** or **Space** toggles one, **Esc** goes back to the field).
- **⌘E** shows or hides a covered clip, like **⌘Return**.
- **⇧Return** pastes the focused clip as plain text, in search too.
- **Page Up**, **Page Down**, **⌥←** and **⌥→** move a screenful of clips (the clips that fit the window, less one).
- **Return** with two or more clips selected starts Paste One by One.
- **←** **→** **Home** **End** move the text cursor while the search field is open.

## 7. Names and words that changed (Wave 3, the voice review)
The site's copy and screenshots must use the app's names. Check every page, screenshot caption and the sample shelf for:
- **Paste As…** (menu item, Title Case; the guide already says *Paste As…*).
- **Change the Shortcut** (onboarding button), **Not Now** (import banner), **Launch Pesto at login** (one name everywhere:
  onboarding, Settings → General and the guide), **Start over** (Settings → Data section), **Clip icon** (popover title).
- **Floating window** is the name of the always-on-top copy of the shelf (never "pinned window").
- Prose says **picture**, not "image", and **clip**, not "card" (the picture file is "Pesto picture" and the date). Names keep
  their word: Describe Image, Save Image to Downloads, the Image chip.
- The **History locked** lock screen label is sentence case.
- The guide's *Paste As…* list: lowercase, UPPERCASE, Title Case, Sentence Case, camelCase, PascalCase, Slug-Case (not
  snake_case or kebab-case), 26 transforms in all; the transform names **Remove Tracking Parameters** and **Slug-Case**.
- Import: Raycast exports are the only snippet file Pesto reads (TextExpander and Alfred can convert theirs to it).
- Settings → General subtitle: "Encrypted on this Mac. Pesto sends no clips anywhere."
- The command-line tool: `pesto copy --concealed`, `pesto last` skips secrets and prints nothing under the History Lock,
  `pesto install` links into `/usr/local/bin` or, when that cannot be written, `~/.local/bin`.
- Undo menu items read as verbs: Edit Note, Edit Tags, Change Icon, Pin or Unpin, Change Shortcut, Change Sensitive Mark,
  Change Expiry, Edit Snippet.
- The private-key mask is `•••• (N characters hidden)`; no padlock emoji anywhere in the app.
- Right-to-left: the arrow keys and the collection slide follow the row; the app itself is English only.
- Keyboard text of the shelf: as in section 6.
- Xcode: Xcode 27 builds everything; Xcode 26 builds without Describe Image and picture screening (if the site says Xcode 26).

## Check
- The sample shelf's covered card has no color.
- No page states a key that is not in `docs/guide/shortcuts.md`.
- Screenshots of the Undo banner and delete question use the filled buttons.
