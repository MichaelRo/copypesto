// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData

extension StorageService {
    /// The tombstone for a clip the person deleted. With sync on it also carries the plain SHA-256 of the text (read
    /// before the clip and its blob go) and a stamp, so another Mac removes its own copy of the same text too; unless a
    /// clip that stays here holds that text (an edit made it so, ADR 0053), when only the id goes.
    func syncTombstone(for item: ClipboardItem, alsoDeleted doomed: [UUID]) -> DeletedItemTombstone {
        applyMayHaveTombstones = true
        let tombstone = DeletedItemTombstone(id: item.id)
        guard let clock = SyncJournal.clock(for: modelContainer) else { return tombstone }
        tombstone.kindRaw = "item"
        if item.sensitivityRaw == nil || item.syncEmittedClock != nil, !textStays(of: item, alsoDeleted: doomed) {
            tombstone.plainHash = item.blob?.decryptedData().map { Data(SHA256.hash(data: $0)).hexString }
        }
        tombstone.changeClock = clock.next().encoded
        tombstone.syncDirty = true
        return tombstone
    }

    private func textStays(of item: ClipboardItem, alsoDeleted doomed: [UUID]) -> Bool {
        let hash = item.contentHash
        let count = try? modelContext.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentHash == hash && !doomed.contains($0.id) }
        ))
        return (count ?? 0) > 0
    }

    func syncCollectionTombstone(id: UUID) -> DeletedItemTombstone {
        applyMayHaveTombstones = true
        let tombstone = DeletedItemTombstone(id: id)
        guard let clock = SyncJournal.clock(for: modelContainer) else { return tombstone }
        tombstone.kindRaw = "collection"
        tombstone.changeClock = clock.next().encoded
        tombstone.syncDirty = true
        return tombstone
    }
}
