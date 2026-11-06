# 0038. A sync folder is read with a size cap on small files, a grant's key is checked before it is kept, and a tombstone holds no hash of a secret

Status: Accepted

Nothing about the network, the encryption, the backup file or the sync file formats changes. These three rules tighten what Pesto does with what it reads from, and writes to, a folder it does not trust (ADR 0018).

## Context
A security review of backup, restore and sync (November 2026) read the code against the threat model of ADR 0018: the folder is untrusted storage, and anyone who can write to it can plant, replace or delete files. Three of its findings were plain defects with no format or crypto decision behind them.

## Decision
- **A file that is small by nature is read through `SyncSmallFile`, which refuses one over 1 MiB** before reading it. A vault, a device record, an identity, a grant and a join request are a few hundred bytes. Before this, each was read whole with `Data(contentsOf:)`, so a multi-gigabyte file planted under one of those names was loaded into memory every time sync looked at the folder. Segments and payload files are still read whole: their size is legitimate and bounded only by a clip (up to 10 MB each, many to a segment), which a later decision may bound.
- **A grant's key is checked with `SyncVault.accepts` before it is saved.** A grant that is validly signed by the approver the person confirmed but carries another key was saved, and because the key store never overwrites, the correct recovery key was then ignored and the Mac was stuck at "needs key". It now fails with the message the other failures give and saves nothing.
- **A deletion tombstone carries no plain SHA-256 for a clip that holds a secret or is a credential** (`sensitivityRaw != nil`). The hash lets another Mac remove its own copy of the same text, but it also let anyone holding the sync key test a guess at a deleted secret offline. The deletion itself still syncs by id. A clip that never syncs gains nothing from the hash.

## Consequences
- Tests: `SyncSmallFileTests`, `SyncSmallFileScanTests` (no new whole-file read of a small file), `aGrantWithTheWrongKeyIsNotSaved`, `deletionOfASecretCarriesNoHash`.
- A sensitive clip that was synced (the person opted in) and is deleted on one Mac is removed on the others by id; one whose id the other Mac does not know is no longer matched by hash.
- Not changed here, and listed in the review note for a decision: the six-word pairing code is short enough to grind (a protocol change), the epoch can be rolled back by hiding a newer vault file, and the passphrase rule is weak.

## Docs affected
- `decisions/README.md`
- `Sources/Core/Sync/CLAUDE.md` (the small-file rule)
