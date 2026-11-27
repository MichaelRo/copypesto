// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData

extension StorageService {
    /// The tombstone for a clip the person deleted. With sync on it also carries the plain SHA-256 of the text (read
    /// before the clip and its blob go) and a stamp, so another Mac removes its own copy of the same text too; unless a
    /// clip that stays here holds that text (an edit made it so, ADR 0053), when only the id goes.
    func syncTombstone(for item: ClipboardItem, textStays: Bool) -> DeletedItemTombstone {
        applyMayHaveTombstones = true
        let tombstone = DeletedItemTombstone(id: item.id)
        guard let clock = SyncJournal.clock(for: modelContainer) else { return tombstone }
        tombstone.kindRaw = "item"
        if item.sensitivityRaw == nil || item.syncEmittedClock != nil, !textStays {
            tombstone.plainHash = item.blob?.decryptedData().map { Data(SHA256.hash(data: $0)).hexString }
        }
        tombstone.changeClock = clock.next().encoded
        tombstone.syncDirty = true
        return tombstone
    }

    /// The clips outside `doomed` that hold the text of a clip in it, by content hash, in one fetch.
    func survivingHolders(of doomed: [ClipboardItem]) throws -> [String: Set<UUID>] {
        let doomedIDs = Set(doomed.map(\.id))
        let hashes = Array(Set(doomed.map(\.contentHash)))
        let holders = try modelContext.fetch(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { hashes.contains($0.contentHash) }
        )).filter { !doomedIDs.contains($0.id) }
        return Dictionary(grouping: holders, by: \.contentHash).mapValues { Set($0.map(\.id)) }
    }

    func syncTombstone(forID id: UUID) -> DeletedItemTombstone {
        applyMayHaveTombstones = true
        let tombstone = DeletedItemTombstone(id: id)
        guard let clock = SyncJournal.clock(for: modelContainer) else { return tombstone }
        tombstone.kindRaw = "item"
        tombstone.changeClock = clock.next().encoded
        tombstone.syncDirty = true
        return tombstone
    }

    func upsertSyncTombstone(forID id: UUID) {
        applyMayHaveTombstones = true
        var descriptor = FetchDescriptor<DeletedItemTombstone>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            guard let clock = SyncJournal.clock(for: modelContainer) else { return }
            existing.kindRaw = "item"
            existing.changeClock = clock.next().encoded
            existing.syncDirty = true
        } else {
            modelContext.insert(syncTombstone(forID: id))
        }
    }

    func recordUserDeletionTombstones(for doomed: [ClipboardItem], survivors: [String: Set<UUID>]) {
        let doomedIDs = Set(doomed.map(\.id))
        var foldedAliasIDs: [UUID] = []
        var seenFolded = doomedIDs
        for item in doomed {
            let textStays = !(survivors[item.contentHash] ?? []).isEmpty
            modelContext.insert(syncTombstone(for: item, textStays: textStays))
            for foldedID in item.metadata.foldedSyncIDs ?? [] where seenFolded.insert(foldedID).inserted {
                foldedAliasIDs.append(foldedID)
            }
        }
        for foldedID in foldedAliasIDs {
            upsertSyncTombstone(forID: foldedID)
        }
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
