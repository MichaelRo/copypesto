# 0049. How a clip was made on an iPhone or iPad is kept on that device only

Status: Accepted (owner request, 2026-11-15)

Extends ADR 0002 (sealed metadata), ADR 0017 (derived data in `ItemMetadata`), ADR 0018 (sync) and ADR 0046. Nothing
they decide is reversed.

## Context
iOS cannot name the app a clip came from, so a card made on the iPhone said "iPhone" at its foot, which tells the
person nothing. The person always knows how they handed it over: the Paste button, a note, the share sheet, a drop or a
Shortcut. That is a fact about this device's history, not about the clip: another device has no use for it, and the
sync format and backups must stay what they are.

## Decision
- **`CaptureMethod`** (`paste`, `note`, `share`, `drop`, `shortcut`; Core `Model`) rides on `PasteboardCapture` and
  ingest seals it into the clip's `ItemMetadata` when it creates the clip (a re-copy of a clip already there keeps what
  it had). The Mac never sets it, so a Mac capture seals nothing more.
- **Never synced or backed up.** It is not part of the sync fingerprint (setting it stamps nothing), an item record has
  no field for it (the record of a clip with one has exactly the fields of a clip without), and the backup lists
  metadata fields by name and does not name it. A clip that arrives by sync has none.
- **The foot line** says "Pasted", "Note", "Shared", "Dropped" or "Shortcut" with the device's symbol for a clip made
  here; a synced clip keeps its app's name (or only its age); a local clip from before this change names the device as
  before.

## Consequences
- `SyncCaptureMethodTests` (run on the Mac and in the iOS test target) and the unchanged `SyncFormatTests` hold the
  format; `CardFootLineTests` the words.
- After a restore from a backup, or on a second device, the method is gone and the device's name shows.

## Docs affected
`docs/design/ios-library.md`, `decisions/README.md`.
