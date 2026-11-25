# The iPhone and iPad library: one page of Pesto cards

Approved by Michael on 2026-11-14 after two design consults; built in `Sources/Mobile` (ADR 0046). The page has to look
and feel like Pesto's shelf: the clip is the card, newest first, ready to use.

## The page
- **Compact width** (an iPhone, an iPad window that is narrow): one `NavigationStack`, no tab bar. Inline title "Pesto"
  (or Pinned, or the collection's name); Settings (gear, a leading slide-in drawer) on the leading side; New Note in its glass circle and, on its own, the
  system Paste button as a filled accent capsule on the trailing side (in one glass group with New Note its square
  background stuck out; `PasteButton` takes no glass style). Under the bar a chip row, then the grid. Search is `.searchable` on the stack: iOS 26 puts
  it in the bottom toolbar on iPhone (seen in the UI tests' hierarchy: the field sits above the keyboard with a close
  button beside it).
- **Regular width** (`PadLibraryView`): a two-column `NavigationSplitView`. The sidebar lists All Clips, Pinned and the
  collections with New Collection; Settings is in its toolbar. Search sits in the grid's top toolbar. A clip opens in a
  trailing `.inspector`, only on demand. With the sidebar hidden the grid carries the chip row and the gear
  (`LibraryChrome.showsChipRow`, driven by the size class and the column visibility, never by the device). A regular
  width under 800 pt (an iPad window in Split View) starts with the sidebar hidden (`LibraryChrome.initialColumns`).
- **A foldable iPhone** follows the same rule as an iPad window: folded it is compact and gets the phone layout;
  unfolded it is regular and gets the iPad layout, with the sidebar hidden while the width is under 800 pt. The root
  decides the columns from the width in either class and builds the split view only once they are decided, so an
  unfold never shows the sidebar and then hides it (`LibraryResizeHostingTests`, at 375, 700 and 800 pt).
  Fold-specific checks (the hinge, a half-open posture) wait for a device.
- **A change of layout** (an iPad window resized across the compact boundary, a fold or an unfold) tears down one
  layout and builds the other, so what the person is doing lives in `LibraryModel` above both: the scope, the search,
  the open clip, the unsaved Edit Text draft (memory only, never `@SceneStorage`, which `no_scene_storage` in
  `.swiftlint.yml` rejects: it would write plaintext to disk) and the first visible card, which the grid scrolls back
  to (`scrollPosition`). `LayoutSwapUITests` flips a forced size class on the iPad simulator, because XCUITest cannot
  resize a window.
- **Chips** (`LibraryChip.row`): All, Pinned, each collection, then "+". While a search is open the row adds the six
  kinds (Text, Links, Pictures, Colors, Code, Files) after a divider and drops "+"; kinds appear nowhere else. A kind
  narrows the scope; ending the search clears it (`LibraryFilter`). A collection chip's menu edits (name, icon, color) or deletes it
  (both undoable). Chips are Pesto's own: a wash of the accent or the collection's color, stronger with a check mark
  when chosen; never glass.
- **Grid** (`CardGridLayout`): `LazyVGrid`, 12 pt gaps and 16 pt margins, columns of at least 190 pt: two on an iPhone
  in portrait, three in landscape, four or five on an iPad, one at an accessibility text size. Cards keep the Mac
  card's 10 by 9 shape and 12 pt continuous corners, a 0.75 pt hairline (0.45 under Increase Contrast), no shadow,
  white on a light ground and white at 10 percent on a dark one, on the theme's solid ground.
- **Order while looking** (`GridOrder`): a copy moves the clip to the front of the history at once, but the grid keeps
  the order it had until the app returns to the front, a pull to refresh, or a change of scope or search; a clip new to
  the grid (a capture, a sync, one that left the scope and came back) is placed by the history's order: after the
  nearest clip above it that the grid already shows, or at the top when none is. Ages at the cards' feet move once a minute (one task in the grid moves
  the minute its cards read; a `TimelineView` around the grid kept it from drawing any change until its next tick).
- **Pull to refresh** runs one sync exchange when sync is on, then takes the history's order again. There is no Sync
  Now; a background refresh exchanges now and then while the app is away (`SyncExchange`).
- **New Collection and Edit Collection** are one sheet: a name, an icon from Core's `CollectionSymbols` and a color from
  `CollectionPalette` (the Mac's lists; an emoji or another icon a Mac set stays offered), saved through
  `CollectionStore` as one undoable change. Sidebar rows and chips show the icon in the collection's color.
- **Clipboard on open** (`ClipboardOffer`): when the clipboard changed while Pesto was away (only its change count and
  whether it holds text, a link or a picture are read, which iOS does not ask about), a banner "Add what you copied"
  offers it with the system Paste button. With Settings → Clipboard → "Add copies when Pesto opens" on (off by
  default) it is read and added at once, and iOS asks for permission. One change is handled once; Pesto's own copy
  is never offered.
- A cold launch lands on All at the top with no keyboard. Empty: the Paste button and one line. The "nothing is saved
  this session" line stays above the grid.

## The card (`CardFace`, built on Core's `CardTreatment`)
| Clip | Card |
|---|---|
| Text | 48 characters or fewer on one line: Core's 24 or 18 pt semibold. Longer: callout, whole lines only. |
| Code | Footnote monospaced. |
| Link | Host semibold on one line (Core's size, shrinks to 0.7), path in caption and secondary; its stored preview picture fills the card instead when there is one. |
| Picture, GIF | Fills the card when its shape is 0.8 to 1.35 (ADR 0041); otherwise shown whole over a blurred, darkened still copy. Facts on pills; a GIF pill. A GIF plays while its card is on screen and not covered, from frames decoded off the main thread within a memory budget (`GIFFrames`); under Reduce Motion it shows its first frame. |
| Color | The card is the color; the text and facts in black or white by Core's `CardInk`. |
| File | Document symbol, name and folder. |
| Secret | The mask, a lock, the category at the foot, an eye that asks for Face ID (`SecretReveal`); after Show, the start of the text and Hide. |
| Covered otherwise | The eye-slash symbol and the kind, nothing else; under the screen-capture cover or Hide Clip Contents (ADR 0054) a Show button that uncovers that card until the cover returns. |
| Locked | No card at all: the lock screen replaces the library (ADR 0054). |

**The foot line** (`CardFootLine`, on Core's `CardMetaLine`): the app's name, or "Another device", or for a clip made on
this device the device's symbol and how it came in (Pasted, Note, Shared, Dropped, Shortcut; ADR 0049), or the device's
name for one made before that was kept; a synced clip without a name shows only its age; a title the person gave
leads. Then the age, then the collection and pin marks. No ⌘ numbers, no size.

## What a person does
- **Tap** copies (a secret too, without showing it, `localOnly` and gone after two minutes), moves the clip to the
  front, flashes an accent ring, plays the success haptic, says "Copied" in a small toast and to VoiceOver. No Undo on
  a copy. Return copies the focused card.
- **Long press**: a large preview and Copy, Copy As (the Mac's text transforms for text, code and links; a color's
  formats), Copy Recognized Text and Save to Photos (a picture; add-only Photos permission), Edit Details, Share, Pin or
  Unpin, Add to Collection, Save as Snippet (a plain text clip), Show (a hidden secret), Delete (last, destructive, Undo
  offered). A snippet that asks for values (ADR 0017) opens a small sheet before Copy: its fields, and a system Paste
  button for `{{clipboard}}` (never a silent read); selection and app name stay empty on iOS. The same copy actions are
  in the detail's More menu. SwiftUI gives a grid no "tap the preview" hook, so Edit Details is
  the way into the detail.
- **Drag**: a card that nothing covers drags out as text, a URL or its picture, with its id visible to Pesto alone
  (`ClipDrag`, an exported type with `.ownProcess` visibility). A drop on a sidebar collection files the clip there; a
  drop of a card back on the grid is ignored; text, links and pictures from other apps dropped on the grid are kept.
- **Detail**: a sheet with medium and large detents on a compact width, the inspector on a regular one: the content at
  full size, title, note and tags edited in place (`ClipDetailFields`, saved through `ClipEditor` when a field is
  submitted or loses focus and only when it changed), Add to Collection, one line of facts with the size, and Copy,
  Share and More (Pin, Delete) in the toolbar. A text, code, link or color clip has Edit Text above its content, one press from the editor: an
  editor with Cancel and Save, saved through Core's `updateText` (ADR 0048) with the Undo banner in the sheet; a hidden
  clip only after Show.
- **Keyboard** (iPad): ⌘N new note, ⌘F search, ⌘I details of the focused card, ⌘C copy selected textual clips (outside search/detail/editors), ⇧⌘C copy, ⇧⌘P pin (⌘P is Print), ⌘⌫ delete with a
  confirmation, ⌘Return Ask Pesto (while searching), all in the menu a held ⌘ shows.
- **VoiceOver**: a card is one element ("Link, copypesto.net, Safari, 4 minutes ago, Pinned"); activating copies (or toggles selection during multi-select);
  actions Edit Details, Pin, Share, Show (Hide once shown) and Delete. The detail's picture says its kind, its size and the start of any text read in it.

## Search and filters
Search reads the history index, then adds clips that match by meaning (`SemanticSearch`, the Mac's threshold and
order: after the text matches) when the on-device model is available. While searching the chip row also offers `When` (Today, Yesterday, Last 7/30 Days, Last 1/3/12 Hours, or a Custom Date Range sheet), `From` (source apps with clip counts), `Sensitive`, `Other Devices` (clips that arrived by sync), and `Ask` (`PadLibraryView` keeps the filter chips visible while searching even with the sidebar open). `Copy All` in `MobileSelectionBar` joins multiple selected text/code clips (`⌘C` or the action bar button) while preserving secret protection. `ClipDetailView` surfaces look-alike clips (`Similar Clips` + `Save as Snippet…`), peer device names, and source apps, while `Settings → Data → Insights` presents `MobileInsightsView`. Link previews are fetched once for a
link card on screen (`LinkPreviewLoader`), only with Settings → Privacy → Load link previews on (off until the welcome's step two switches it on, with the switch in view, or the person does; ADR 0057) and never while locked. A GIF copied in Safari arrives as a still and its address,
and the whole GIF is fetched under the same switch (`RemoteGIFFetcher`). Settings → History has Keep clips for and Keep
at most with the Mac's choices and defaults, swept at launch and, at most hourly, on return to the foreground.

## Motion
Only `Motion.animation` with the four named curves: cards entering and leaving the grid (one clip added or removed;
`ListChangeMotion`), the chip and the Copied ring, the toast, the detail's edit switch, and the lock screen fading in
(the library leaves at once, so no card stays drawn while it fades). Nothing under Reduce Motion, nothing before a tap.

## Theme
`MobileAccent` resolves the ground and the accent with `MobileTheme` (Core's `AppTheme`, `AccentChoice` and
`ContrastRatio.readable`, as the Mac's roots do) and sets `pestoAccent`, `pestoAccentLabel` and `pestoSurface` once.
Settings → Appearance has the theme, System, Light or Dark, the accent and the app icon (the four theme icons, chosen
on their own: iOS confirms each change with an alert), set on every window's `overrideUserInterfaceStyle`
(`MobileAppearanceBridge`).
Per device: these preferences are not synced. Liquid Glass is only the system's bars, search field, sheets and menus.

## The Recent Clips widget (ADR 0052)
Pesto cards at widget scale on the theme's ground carried in the snapshot: one card fills the small widget, three sit
in a row in the medium one, six in two columns in the large one. A color fills its card, a picture fills it near a
card's shape, a link leads with its host, short text is large, one foot line gives the source and `CardAge`. The
widget's own setting chooses what a tap does: Copy (in place for a short text, else Pesto copies and flashes the card),
Open in Pesto (the detail) or Open the Clip (a link in Safari); Show chooses Recent, Pinned or Collection, and then
which collection, from those the snapshot carries (ADR 0060): "No clips in this collection yet" when it is empty,
"Choose a collection" when none is chosen or it is gone. With the History Lock on it says "Locked" and "Open Pesto to see your clips." unless "Show clips in widgets, AutoFill and the keyboard while locked" is on (ADR 0055).

**Lock Screen widgets (ADR 0065):** `LockScreenClipsWidget` (`AppIdentity.lockScreenWidgetKind`) offers circular,
rectangular, and inline accessory families on iPhone and iPad. By default, **Show Clips on Lock Screen** is off so no
clip content appears on a locked phone until the person turns it on in that widget's settings; secrets never enter the
snapshot, History Lock still hides clips unless allowed while locked, and **When Chosen** lets that widget copy the
clip (`Copy Clip`, default via `WidgetLink.url(for: clip.id)`), open Pesto (`Open Pesto`), or open the clip detail
(`Open Clip`), always unlocking iOS first via `.widgetURL`.

## The keyboard (ADR 0061)
Optional, added in iOS Settings. No letter keys. A small shelf (ADR 0062): chips like the Mac shelf's (Recent, Pinned,
Snippets, then the collections chosen in Settings → AutoFill and keyboard → Collections), and the clips as small Pesto
cards in a row that scrolls sideways, two rows on iPhone and one on iPad, each with the kind's glyph and a laptop when
it came from another device; snippets shown as they would insert. The word typed before switching is the search: it
leads the chips in quotes, and picking a card replaces it. A "123" pad of numbers and punctuation; Space, Return and
Delete, with the globe key when iOS asks for it. A tap inserts and returns to the person's keyboard, or stays, as
"After inserting a clip" says; a long press does the other. Without Full Access the pad and one line on Full Access;
with no set one line on turning on Insert from Pesto; with an empty one "No text clips yet." The magnifying glass opens
the search page (ADR 0063): Pesto's own search field, the matches in one row, letters or numbers that type only into
that field, and Done; the keyboard grows 40 points while it is open.

## FAQ for the release notes: Add Clipboard to Pesto
The guide has no iPhone section until the app is released (ADR 0046), so this entry waits here and moves to
`docs/guide/faq.md` with the rest.

**How do I add what I copied without opening Pesto first?** Shortcuts lists "Add Clipboard to Pesto" (Pesto's own
action; Siri answers "Add my clipboard to Pesto"). It brings Pesto to the front, reads the clipboard, adds it as a clip
that says it came from a Shortcut, and says "Added to Pesto." Pesto opens because iOS lets only an app on screen read
what another app copied; iOS asks to allow the paste unless Settings → Apps → Pesto → Paste from Other Apps is set to
Allow. A locked history (Face ID) adds nothing until you unlock.
- **Action Button** (iPhone 15 Pro and later): Settings → Action Button → Shortcut → choose "Add Clipboard to Pesto".
- **Back Tap**: Settings → Accessibility → Touch → Back Tap → Double Tap or Triple Tap → choose "Add Clipboard to
  Pesto" under Shortcuts.
- **An automation**: Shortcuts → Automation → New Automation → App → Safari → Is Closed (or any app), Run Immediately →
  New Blank Automation → add "Add Clipboard to Pesto". Copy in Safari, close it, and the clip is waiting.

## The welcome (ADR 0057)
Three steps once over the library (iPhone full screen, iPad form sheet; Skip on every step; Settings → Show Welcome Again), then a one-time AutoFill tip after the first pin or snippet. `-UITest` launches skip it unless `uitestShowsWelcome` / `uitestShowsAutoFillTip` is set.

## What pass 3 brought over (ADR 0058)
- **Decode JWT**: in the menu of a hidden token, after the same Face ID question as Show; a sheet with the header, the payload, the times and "Not verified"; Copy Payload copies it as a secret.
- **Copy As** leads with JSON and Markdown for a clip that qualifies (a table, a JSON document, HTML), as the Mac's does.
- **GIF**: a GIF shared into Pesto, pasted or dropped keeps every frame; Share from a card or the detail hands over a `.gif` file.
- **AI Actions** (a submenu of a card's menu and the detail's More menu): Summarize, Key Points, Professional, Concise, Translate and Extract on text and code, Describe Image on a picture, on Apple's on-device model. Greyed out with the reason while it is off or getting ready; hidden on a device that never can; never offered for a hidden clip. The answer is a sheet with Copy (kept as a clip) and Done. Settings → Apple Intelligence has the one switch.
- **Ask**: while searching with words typed, an Ask chip leads the filters; one tap makes the kinds and the date from the sentence, shown as one chip that takes them off again.
- **Smart collections**: New Collection → Smart, then rules as grouped Form sections; Edit Collection shows them again.

## Left out on purpose
A tab bar, a list or a list/grid toggle, sort menus, swipe actions, a pushed detail screen, a Kinds
section, a keyboard with typing keys (the optional keyboard has none, ADR 0061), glass on a card, reading a long text for AI a part at a time (the Mac does; the iOS answer says how much was read).
