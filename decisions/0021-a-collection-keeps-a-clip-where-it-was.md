# 0021. A collection keeps a clip where it was; only the history moves it on use

Status: Accepted

Relates to [0007](0007-storage-and-app-state.md) (the history store) and [0002](0002-clip-data-is-sealed-at-rest.md)
(sealed metadata).

## Context
A clip has one date, `timestamp`. A paste, a copy from the shelf and a re-copy of the same content all overwrite it, so
the clip moves to the front of the history. A regular collection lists the clips the person placed by hand
(`collectionOrder`) first and the rest by `timestamp`, newest first. A paste therefore moved a clip to the front of its
collection too, and a collection the person had arranged by habit rearranged itself every time they used it. The
"All" view is meant to follow use; a collection is meant to stay put.

## Decision
- `timestamp` keeps meaning "last used": the history, search and smart collections order by it as before.
- The time a clip was first copied is kept in sealed metadata (`ItemMetadata.copiedAt`), written the first time a use
  moves `timestamp`, from the value `timestamp` held before. Every place that moves a clip to the front goes through
  `ClipboardItem.bringToFront(at:)`. A clip never used has no `copiedAt` and reads it from `timestamp`.
- A regular collection orders by hand position first, then by `copiedAt`, newest first (`CollectionOrder.sorted`, in
  Core, so it is tested without a view). A use does not move a clip inside a collection.
- The "Copied" line of the detail card shows `copiedAt`, the first copy, not the last paste.

Written on first use rather than at ingest so a capture seals no extra metadata (the capture budget of 200 ms and the
store size are untouched), and a clip that joins a collection after being pasted still keeps its first copy time.

## Consequences
- The first paste of a clip seals one small piece of metadata. Nothing new is stored in the clear.
- **Sync** carries it in the clip's record (`SyncCuration.copiedAt`, absent for a clip never used and in older
  records). It is not part of the sync fingerprint: a paste is this Mac's own business and writes no record, as before,
  so the value travels with the next record the clip gets (its first one, on a new Mac, carries it). The earliest
  value wins on every Mac (`ClipboardItem.adoptFirstCopy`), even from a record whose edits lose on the stamp, so the
  result does not depend on the order records arrive in. A Mac that only received a clip does not write it back, so
  two Macs that copied the same text independently agree once the earlier one writes a record for it.
- **Backups** carry it (`BackupItemMetadata.copiedAt`) together with `collectionOrder`, which backups had never kept:
  a restore used to lose a collection's hand order. Both are absent in older backups and read as none.
- Clips used before this change have no first-copy time; they order by their last use until the next use, which
  keeps that value from then on.

## Docs affected
- `docs/guide/` (Collections: a paste does not reorder a collection)
- `docs/guide/settings.md` (Backup: a clip's place in a collection is kept)
- `decisions/README.md` (this record in the table)
