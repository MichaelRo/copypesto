# 0043. A Paste import reads the payloads Core Data keeps in external files

Status: Accepted

Extends ADR 0011 and ADR 0032; nothing they decide is reversed.

## Context
Paste is a Core Data app, and its payload column allows external storage. Core Data keeps a small value in the column (marker byte 0x01, then the bytes) and moves a large one into a file beside the store: the column then holds marker 0x02, the file's UUID name and a NUL, and the bytes, without a marker, are in `.Paste_SUPPORT/_EXTERNAL_DATA/<UUID>` (verified on a store Core Data wrote; Apple does not document it). The importer read only the column and copied only `Paste.db`, `-wal` and `-shm`, so every large picture and file was counted as undecodable and planned at a few dozen bytes. A library of 1,079 mixed clips imported to 1.9 MB.

## Decision
- The snapshot reads the external folder in place, read-only, and does not copy it (pictures can be gigabytes; the copy of the database is what protects against a running Paste).
- A reference is followed only when it is a plain UUID name. The file is opened with `O_NOFOLLOW`, must be a regular file, and is sized from the open descriptor; one over `maxRecordBytes` is never read. A name with a slash, a link, a missing file or a missing folder is counted, never followed.
- The plan uses the file's real size, so the cap and the batches are right.
- The sheet says why clips cannot come in (empty, over 50 MB, or lost their file) instead of "pictures or empty", and, when clips from an earlier import are found, that importing again brings in what was left out. Re-importing needs no new mechanism: clips already in Pesto are skipped by copy time and by `ingest`'s content hash.
- Clips still go through `PasteMigrator` and `StorageService.ingest`.

## Consequences
- A file Paste deletes between the plan and the read is counted as left out in the summary.
- The importer now reads one folder the person did not pick by hand, a sibling of the library they chose.

## Docs affected
`docs/guide/moving-from.md`.
