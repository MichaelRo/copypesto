# The iPhone and iPad library: one page of Pesto cards

Approved by Michael on 2026-11-14 after two design consults; built in `Sources/Mobile` (ADR 0046). The page has to look
and feel like Pesto's shelf: the clip is the card, newest first, ready to use.

## The page
- **Compact width** (an iPhone, an iPad window that is narrow): one `NavigationStack`, no tab bar. Inline title "Pesto"
  (or Pinned, or the collection's name); Settings (gear, a sheet) on the leading side; the system Paste button and New
  Note on the trailing side. Under the bar a chip row, then the grid. Search is `.searchable` on the stack: iOS 26 puts
  it in the bottom toolbar on iPhone (seen in the UI tests' hierarchy: the field sits above the keyboard with a close
  button beside it).
- **Regular width** (`PadLibraryView`): a two-column `NavigationSplitView`. The sidebar lists All Clips, Pinned and the
  collections with New Collection; Settings is in its toolbar. Search sits in the grid's top toolbar. A clip opens in a
  trailing `.inspector`, only on demand. With the sidebar hidden the grid carries the chip row and the gear
  (`LibraryChrome.showsChipRow`, driven by the size class and the column visibility, never by the device).
- **Chips** (`LibraryChip.row`): All, Pinned, each collection, then "+". While a search is open the row adds the six
  kinds (Text, Links, Pictures, Colors, Code, Files) after a divider and drops "+"; kinds appear nowhere else. A kind
  narrows the scope; ending the search clears it (`LibraryFilter`). A collection chip's menu renames or deletes it
  (both undoable). Chips are Pesto's own: a wash of the accent or the collection's color, stronger with a check mark
  when chosen; never glass.
- **Grid** (`CardGridLayout`): `LazyVGrid`, 12 pt gaps and 16 pt margins, columns of at least 190 pt: two on an iPhone
  in portrait, three in landscape, four or five on an iPad, one at an accessibility text size. Cards keep the Mac
  card's 10 by 9 shape and 12 pt continuous corners, a 0.75 pt hairline (0.45 under Increase Contrast), no shadow,
  white on a light ground and white at 10 percent on a dark one, on the theme's solid ground.
- A cold launch lands on All at the top with no keyboard. Empty: the Paste button and one line. The "nothing is saved
  this session" line stays above the grid.

## The card (`CardFace`, built on Core's `CardTreatment`)
| Clip | Card |
|---|---|
| Text | 48 characters or fewer on one line: Core's 24 or 18 pt semibold. Longer: callout, whole lines only. |
| Code | Footnote monospaced. |
| Link | Host semibold on one line (Core's size, shrinks to 0.7), path in caption and secondary; its stored preview picture fills the card instead when there is one. |
| Picture, GIF | Fills the card when its shape is 0.8 to 1.35 (ADR 0041); otherwise shown whole over a blurred, darkened still copy. Facts on pills; a GIF pill. Never animated on a card. |
| Color | The card is the color; the text and facts in black or white by Core's `CardInk`. |
| File | Document symbol, name and folder. |
| Secret | The mask, a lock, the category at the foot, an eye that asks for Face ID (`SecretReveal`); after Show, the start of the text and Hide. |
| Covered otherwise | The eye-slash symbol and the kind, nothing else. |

**The foot line** (`CardFootLine`, on Core's `CardMetaLine`): the app's name, or "Another device", or for a clip made on
this device the device's symbol and name; a synced clip without a name shows only its age; a title the person gave
leads. Then the age, then the collection and pin marks. No ⌘ numbers, no size.

## What a person does
- **Tap** copies (a secret too, without showing it, `localOnly` and gone after two minutes), moves the clip to the
  front, flashes an accent ring, plays the success haptic, says "Copied" in a small toast and to VoiceOver. No Undo on
  a copy. Return copies the focused card.
- **Long press**: a large preview and Copy, Edit Details, Share, Pin or Unpin, Add to Collection, Show (a hidden
  secret), Delete (last, destructive, Undo offered). SwiftUI gives a grid no "tap the preview" hook, so Edit Details is
  the way into the detail.
- **Drag**: a card that nothing covers drags out as text, a URL or its picture, with its id visible to Pesto alone
  (`ClipDrag`, an exported type with `.ownProcess` visibility). A drop on a sidebar collection files the clip there; a
  drop of a card back on the grid is ignored; text, links and pictures from other apps dropped on the grid are kept.
- **Detail**: a sheet with medium and large detents on a compact width, the inspector on a regular one: the content at
  full size, title, note and tags edited in place (`ClipDetailFields`, saved through `ClipEditor` when a field is
  submitted or loses focus and only when it changed), Add to Collection, one line of facts with the size, and Copy,
  Share and More (Pin, Delete) in the toolbar.
- **Keyboard** (iPad): ⌘N new note, ⌘F search, ⌘I details of the focused card, ⇧⌘C copy, ⌘P pin, ⌘⌫ delete with a
  confirmation, all in the menu a held ⌘ shows.
- **VoiceOver**: a card is one element ("Link, copypesto.net, Safari, 4 minutes ago, Pinned"); activating copies;
  actions Edit Details, Pin, Share, Show and Delete.

## Theme
`MobileAccent` resolves the ground and the accent with `MobileTheme` (Core's `AppTheme`, `AccentChoice` and
`ContrastRatio.readable`, as the Mac's roots do) and sets `pestoAccent`, `pestoAccentLabel` and `pestoSurface` once.
Settings → Appearance has the theme and System, Light or Dark, applied once with `.preferredColorScheme` at the root.
Per device: these preferences are not synced. Liquid Glass is only the system's bars, search field, sheets and menus.

## Left out on purpose
A tab bar, a list or a list/grid toggle, sort menus, counts on chips, swipe actions, a pushed detail screen, a Kinds
section, onboarding, widgets, a keyboard extension, glass on a card. Source-app chips: Core's index keeps the bundle id
private and iOS cannot name an app, so there is no cheap list to show. The capture method (Paste, Note, Drop) is not
stored with a clip, so a clip made here names the device instead.
