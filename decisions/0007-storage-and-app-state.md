# 0007. Clips live in a light item and a sealed blob inside PestoCore, one observable history store feeds the shelf, and Core is a one-way graph of directories

Status: Accepted

## Context
A clip can carry megabytes of payload; a grid query must never load it. History must stay portable between Macs through
the backup (ADR 0010). The storage engine once lived only in the app target, so a third of it was outside the fast
package tests. Whole-table launch migrations blocked ingest, delete and backup, and a failed `save()` left its changes
for the next save to commit. SwiftData's `#Index` reaches only a new store: a store from the previous build opens with
no index and no error. `AppState` as an `ObservableObject` redrew every view on any change, two full-history `@Query`
fetches stayed live, and a keystroke over 5,000 clips cost 79 ms.

## Decision
**Two models per clip.** `ClipboardItem` holds the metadata the shelf lists. `ClipboardBlob` holds the payload:
`encryptedData` is `@Attribute(.externalStorage)` and always ciphertext (ADR 0002). The 1:1 link is
`@Relationship(deleteRule: .cascade)`. List queries select items only and never traverse `blob`.

**Collections** are rows of `Pinboard`, referenced from a clip by the scalar `ClipboardItem.collectionID`, never a
relationship, so membership travels as a plain field in a backup. They live in the clips store. "Collection" is the name
people see (settings, AppleScript `list collections`, `pesto://collection?name=`); the `@Model` keeps the class name
`Pinboard` because a rename needs a versioned migration, `ClipCollection` is the typealias new code uses, and the column
keeps its name through `@Attribute(originalName: "pinboardID")`. `pesto://pinboard` stays a deprecated alias
(`AutomationAction`). Smart collections store typed rules (`SmartCollectionPredicate`, rule-set version 1 or 2, never a
predicate string); `canCompileRuleSet` says whether this Mac understands a version.

**The engine is in `PestoCore`** (`Storage/Models`, built with Xcode's toolchain), so storage tests run in the package
loop; a storage type is `public` only when the app uses it.
- A whole-history pass goes through `StorageService.forEachClip`: it reads ids, then fetches, visits and saves one page
  of 50 at a time and yields the actor. A clip deleted between pages is skipped, a throw rolls back that page, an
  interrupted pass keeps finished pages. A migration asks only for rows it will change.
- Every save in `StorageService` is `saveOrRollback()`; a direct `modelContext.save()` fails `StorageSaveTests`.
- A preview that cannot be sealed fails the copy (`try`, never `try?`).
- **Schema changes need a versioned stage.** The schema is `PestoSchemaV1` under `PestoMigrationPlan`, whose stage list
  is empty. Additive attributes with defaults need no stage. A new index, a renamed `@Model`, a changed attribute type
  or a new unique rule needs a copy of the old models, a stage and a test that opens an on-disk store written by the
  previous version. Pesto uses no `#Index`: at 5,000 clips the lookups take milliseconds, and a stage is a bigger risk
  to every existing history.

**App state.** `AppState` is `@Observable`; what views must not track is `@ObservationIgnored`; views read
`@Environment(AppState.self)`. `HistoryStore` is the only reader of the history for the shelf and the floating window:
it fetches once on the main context, loads at launch (`prefetch`), then follows each save from what changed
(`HistorySaveChange`, from `ModelContext.didSave`). A change over 200 clips, a save that does not say what changed, one
during the index build, or memory pressure (`trim`) rereads everything. No view holds an unbounded `@Query`
(`UnboundedQueryTests`). `HistoryIndex` keeps one plain-value `HistoryRow` per clip, with a folded byte string of
preview, title, note and tags joined by `0x01`, so a keystroke reads no SwiftData property. It is built in slices of 250
rows, 4 ms apart, and finished synchronously if a search arrives first; an edit calls `refreshRow(for:)`. It holds
folded plaintext in memory only, so the History Lock and a clear drop it (`HistoryStore.dropSearchText`).

**Core layering.** `PestoCore` is one module, so `CoreDirectoryCycleTests` enforces the graph between its directories:
`Model` imports nothing and may always be used; every other edge is named in `allowedEdges`, the list may shrink and
never grow, and the directories form no loop of any length (the scan reads code only). Today: `Runtime`, `Imaging` and
`Predicate` are leaves. `Crypto` and `Backup` sit on `Runtime`; `AI` on `Imaging` and `Runtime`; `Sync` on `Crypto` and
`Runtime`; `Pasteboard` on `Imaging` and `Runtime`; `Search` on `AI`; `Intelligence` on `Predicate`. `Storage` sits on
all of those; `Paste`, `Security` and `Import` on `Storage`; `Seeding` on `Pasteboard` and `Runtime`. A type a lower
directory needs moves down or behind a protocol. There is no separate storage or model target yet: it would turn a scan
failure into a compile error for a rule not broken since the history store landed, at the price of a `public` surface
and an unproven store migration. Re-open it only with a measured build-time and test-time comparison.

## Consequences
- Two models stay in step; anything touching a payload goes through the blob and its sealing.
- `Pinboard` is in storage code while the interface says Collection; the rename can ride the next real schema stage.
- A new pass is written with `forEachClip`; it is interruptible and invisible.
- A keystroke over 5,000 clips costs about 1 ms in the Debug host and 0.2 ms optimized (budget 4 ms); the index costs
  about 3 MB and about 70 ms to build off the frame.
- A new field the shelf filters by is a `HistoryRow` field and a case in `HistoryIndexParityTests` (index against the
  `ShelfFilter` pipeline over 1,056 combinations).
- `Features/` imports `AppState` from `App/` in one module, so that layering is a scan (`ModuleBoundaryTests`), not a
  compiler rule.
- Tests: `OnDiskEncryptionTests`, `BackupRoundTripTests`, `AutomationActionTests`, `LaunchMigrationPagingTests`,
  `StorageSaveTests`, `ContentHashMigrationTests`, `PreviewSealingFailsClosedTests`, `AppStatePublishingTests`,
  `HistoryStoreTests`, `HistoryIndexTests`.

## Docs affected
`Sources/Core/Storage/CLAUDE.md`, `docs/development.md`, `AGENTS.md` (module boundaries line lists the directory order).
