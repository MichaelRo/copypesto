// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// What restoring a backup would do to this Mac. `wouldAdd` is an upper bound: a picture that looks like one already
/// here is only recognized when it is stored.
public struct BackupRestorePreview: Sendable, Equatable {
    public var wouldAdd = 0
    public var alreadyHere = 0
    public var deletedHere = 0
    public var newCollections = 0
    public var wouldRemove = 0

    public init(
        wouldAdd: Int = 0,
        alreadyHere: Int = 0,
        deletedHere: Int = 0,
        newCollections: Int = 0,
        wouldRemove: Int = 0
    ) {
        self.wouldAdd = wouldAdd
        self.alreadyHere = alreadyHere
        self.deletedHere = deletedHere
        self.newCollections = newCollections
        self.wouldRemove = wouldRemove
    }
}

public extension StorageService {
    /// The same decisions `restore(_: VerifiedBackup)` makes, in the same order (deletions, collections, then each
    /// clip),
    /// without writing anything and without `ingest`. Clips are read one at a time, so a large file stays out of
    /// memory.
    func previewRestore(_ backup: VerifiedBackup) async throws -> BackupRestorePreview {
        var preview = BackupRestorePreview()
        var deleted = try Set(modelContext.fetch(FetchDescriptor<DeletedItemTombstone>()).map(\.id))
        for record in backup.smallRecords where record.kind == .tombstone {
            guard let tombstone = try? record.tombstoneMetadata() else { continue }
            deleted.insert(tombstone.id)
            let id = tombstone.id
            if try modelContext.fetchCount(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })) > 0 {
                preview.wouldRemove += 1
            }
        }
        var collectionIDs = try Set(modelContext.fetch(FetchDescriptor<Pinboard>()).map(\.id))
        for record in backup.smallRecords where record.kind == .collection {
            guard let board = try? record.collectionMetadata() else { continue }
            if collectionIDs.insert(board.id).inserted { preview.newCollections += 1 }
        }
        try await backup.forEachItem { record in
            guard let meta = try? record.itemMetadata() else { return }
            if deleted.contains(meta.id) {
                preview.deletedHere += 1
            } else if try alreadyHas(itemID: meta.id, plainHash: meta.plainHash) {
                preview.alreadyHere += 1
            } else {
                preview.wouldAdd += 1
            }
        }
        return preview
    }
}
