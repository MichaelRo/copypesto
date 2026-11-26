# 0081. A collection can be locked on this device

Status: Accepted (owner, 2026-11-26, backlog: lock or hide a whole collection)

Builds on ADR 0003 (one authentication window, Show asks), ADR 0054 (the iOS History Lock) and ADR 0055 (what widgets
and AutoFill hold while locked), whose off-by-default switch this ADR restores.

## Context
- The History Lock is all or nothing. People keep a few things (account numbers, a medical note, a draft) in one
  collection and want that collection behind Touch ID or Face ID while the rest of the history stays at hand.
- A clip belongs to at most one plain collection (`ClipboardItem.collectionID`); a smart collection is a query. All,
  Recent, search, the widget's newest clips and the keyboard's recent clips include clips that are in collections, so
  hiding only the collection's chip would leave its clips readable everywhere else.
- Syncing a lock means a new `Pinboard` column (the store's first schema migration) and a sync field that an older
  build would clear when it edits the collection. The History Lock itself is a setting of each device.
- `Setting.showsClipsOutsideWhileLocked` was changed to on by default in #196 with no ADR, while ADR 0055 and
  `docs/design/ios-keyboard.md` say off.

## Decision
- **Per device.** `Setting.lockedCollections` lists the locked collections' ids on this Mac, iPhone or iPad. Nothing
  about it syncs or is backed up; a clip synced into a collection locked here is locked here by its id.
- **Plain collections only.** A smart collection is a rule over the whole history; locking it would hide clips that
  merely match. Its menu has no Lock item.
- **One policy, in Core**: `CollectionLock` (locked and opened ids) and `LockedCollections` (the stored list).
  - In Pesto: a locked collection's clips show only on its own chip, after it is opened. They never join All, Pinned,
    a search across everything, a search by meaning or a smart collection, opened or not (`HistoryCriteria`).
  - Outside Pesto they are never offered, opened or not: every `ShortcutClipSearch` function takes the locked set (no
    default, so a new caller cannot forget it), and through it Shortcuts on both platforms, AppleScript search and
    paste, widget links, the widget snapshot and the keyboard and AutoFill set leave them out, with their collections'
    chips. The last-item file is cleared when its clip is in, or moves into, a locked collection.
- **Opening** asks through the one authentication window (`AuthenticationGrace`): in the shelf on the Mac
  (`authenticateInShelf`), Face ID, Touch ID or the passcode on iOS (`SecretReveal`). What was opened closes with the
  shelf, when the app leaves the foreground, with the History Lock and when the screen sleeps. `AppState.writeItem`
  writes nothing for a clip whose locked collection is not open.
- **The chip stays**, with a lock (a small lock after the name on the Mac; the lock as its icon on iOS) and "Locked"
  for VoiceOver. An unopened locked chip shows "This collection is locked" and Unlock.
- **Locking needs nothing; unlocking, deleting and exporting a locked collection ask first.** The lock's id outlives a
  delete, so Undo brings the collection back locked. Moving a clip into a locked collection needs nothing.
- `Setting.showsClipsOutsideWhileLocked` is **off by default** again, as ADR 0055 decided. An install that stored a
  value keeps it.

## Consequences
- A person can keep most of the history quick and a few things behind authentication, on each device they choose.
- A collection locked on the Mac is not locked on the iPhone until it is locked there too. The Settings and docs say
  so; syncing the lock would need a store migration and is not done.
- Deleting a locked collection (after asking) leaves its clips in the history like any deleted collection's.
- Installs that never touched "Allow in Widgets and Keyboard while locked" stop showing clips in widgets, the keyboard
  and AutoFill while the History Lock is on.

## Docs affected
- `decisions/README.md`, `decisions/0055-widgets-and-autofill-while-the-ios-lock-is-on.md` (accepted, unchanged)
- `README.md`, `docs/guide/privacy-and-security.md`, `docs/guide/using-pesto.md`, `docs/design/ios-library.md`
- `AGENTS.md`, `Sources/Core/Storage/CLAUDE.md`
