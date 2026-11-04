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
- Sync does not carry `copiedAt` yet: a Mac that receives a clip orders it in collections by the synced `timestamp`,
  which moves on a paste on another Mac. Carrying it is a change to the sync record format (ADR 0018) and is left for a
  later record. Backups do not carry it, as they do not carry `collectionOrder`.
- Clips used before this change have no `copiedAt`; their first copy time is lost and they order by their last use
  until the next use, which keeps that value from then on.

## Docs affected
- `docs/guide/` (Collections: a paste does not reorder a collection)
- `decisions/README.md` (this record in the table)
