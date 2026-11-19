# 0060. A widget can show one collection, from collections the sealed snapshot carries

Status: Accepted (owner request, 2026-11-19)

Supersedes the part of ADR 0052 that says "A collection is not offered" and amends what its snapshot holds and how large
it may be. Extends ADR 0059 (the Mac widget), which shares the snapshot. Everything else they decide stands.

## Context
The widget's Show setting offered Recent or Pinned. People keep clips they reach for in collections, and asked for a
widget of one. ADR 0052 refused it because the widget may read nothing but the sealed snapshot: it cannot open the
store to list collections or match a smart collection's rules. The answer is to put what a collection widget needs into
the snapshot, under the same rules as the clips already there.

## Decision
- **The setting.** Show gains **Collection** (`WidgetSourceChoice.collection`, `WidgetClipSource.collection(UUID?)`),
  and with it a **Collection** parameter, shown only when Show is Collection (`ParameterSummary` with `When`). Its
  picker is a `WidgetCollectionEntity` whose `EntityQuery` reads only `WidgetSnapshotReader.read()?.collections`; the
  extension still never opens the store (`WidgetExtensionReachTests`). Filters (a kind, an app, a search) are not
  offered.
- **What the snapshot adds** (`WidgetSnapshot`, all optional in the format, so no version change and an older snapshot
  opens with none): `collections`, the first `WidgetSnapshotPolicy.maxCollections` (24) collections by `sortOrder`,
  each its id, name (60 characters), SF Symbol name (60), color and whether it is smart, never its rules or trigger app;
  `collectionClipIDs`, each collection's clip ids in its order; and `collectionClips`, the clips a collection shows
  that neither Recent nor Pinned holds, each once. `clips` and `pinned` are unchanged, so Recent and Pinned show
  exactly what they did.
- **Which collections**: the first 24 by `sortOrder` alone, as the apps' own collection lists sort them, so the cap
  leaves out the ones the person sees last.
- **Which clips** (`WidgetSnapshotSelection.members`): a plain collection's newest `collectionScanLimit` (300) members
  (`collectionID`, by last use) in `CollectionOrder.sorted` (the hand order, then first copied, newest first); a smart collection's matches by its
  `PredicateRuleSet` among the newest `smartScanLimit` (300) clips, newest first, and none when its rules do not decode
  or compile. Each keeps at most `maxClips` (8) that `ShortcutClipSearch.isOfferedOutsidePesto` allows: never a secret,
  a clip being judged, a flagged clip or one that expires. Each clip is read as ADR 0052 says; a collection's clip
  gets a thumbnail or whole text only from what Recent and then Pinned left of those budgets.
- **The file's bound rises from 512 KB to 1.5 MB.** The fullest snapshot the bounds allow (every field at its limit
  in characters JSON writes as six bytes, every thumbnail and whole-text budget spent, 24 collections of eight clips no
  other list shares) measured 1,099,583 bytes sealed (`WidgetSnapshotSelectionTests`); 1.5 MB leaves it a third to
  spare. The quick-insert set already allows 2 MB. A real snapshot is far smaller.
- **The widget's states.** A collection with no clips that may be shown: "No clips in this collection yet", with the
  collection's symbol. No collection chosen, or one the snapshot does not carry (deleted, or past the first 24):
  "Choose a collection" and "Edit the widget to choose the collection it shows." Locked and Hidden still come first,
  and their snapshots carry no collection.
- **Changes.** A collection renamed, recolored, reordered or deleted is a save to the store, which rewrites the
  snapshot a second later on both platforms (`ModelSaveObserver`), as a clip change does.
- **Links.** A tile in a collection widget opens the same `pesto://clip/<UUID>` links; the app re-checks the clip by id
  as before, so a clip that became a secret since the snapshot was written is refused (tests on both platforms). An
  in-place copy on iOS reads the clip's whole text from whichever list holds it.

## Consequences
- What sits outside the store while a widget is installed now also holds the first 24 collections' names, symbols and
  colors, and up to 192 more previews of clips that may leave Pesto, sealed as before; at most 1.5 MB.
- Both windows bound a rewrite's cost, which runs a second after every save while a widget is installed. A plain
  collection orders only its newest 300 members, so a clip placed by hand but older than those is missing from its
  widget while Pesto shows it; a smart collection sees only the newest 300 clips, so an old match is missing the same
  way. Measured in a debug build (`WidgetSnapshotPerformanceTests`, sealed metadata on every clip, none opened yet):
  one plain collection of 5,000 clips took about 170 ms to choose before the window and 13 ms with it (budget 50 ms);
  5,000 clips spread over 24 plain collections take about 180 ms either way, since each holds about 208 (budget
  400 ms). About 100 ms of that is the 24 fetches themselves, not the metadata opens.
- Whether WidgetKit offers the Collection picker as expected on the Home Screen and the Mac desktop, and drops a
  deleted collection from a widget's settings, is a hand check: the tests cover the snapshot, the states, the drawing and
  the configuration's mapping, not the system picker.

## Docs affected
`AGENTS.md` (security invariant 2, the snapshot's contents and bound), `README.md` (Features), `docs/guide/automation.md`
(the widget), `docs/guide/privacy-and-security.md`, `docs/design/ios-library.md`, `decisions/README.md`, and ADR
0052's status line.
