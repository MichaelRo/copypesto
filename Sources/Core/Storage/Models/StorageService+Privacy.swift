// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

public extension StorageService {
    private static let privacyLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "Privacy")

    func privacySnapshot() throws -> PrivacySnapshot {
        let clips = try modelContext.fetchCount(FetchDescriptor<ClipboardItem>())
        let pinned = try modelContext.fetchCount(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.isPinned }))
        let masked = try modelContext.fetchCount(
            FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.sensitivityRaw != nil })
        )
        var oldestQuery = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)])
        oldestQuery.fetchLimit = 1
        let oldest = try modelContext.fetch(oldestQuery).first?.timestamp
        return PrivacySnapshot(clipCount: clips, pinnedCount: pinned, maskedSecretCount: masked, oldest: oldest)
    }

    /// The panic button: every clip, pinned ones included, and every collection, with the copies kept elsewhere (link
    /// pictures, the last-item file, the decrypted preview cache). Then the install key is replaced: deleting a row
    /// leaves
    /// its sealed bytes in SQLite's freed pages and write-ahead log until they are reused (measured, see
    /// `ClearEverythingResidueTests`), and without the old key they cannot be opened. If the key cannot be replaced the
    /// clips are still gone; the failure is logged and the old key stays. Returns how many clips were removed.
    @discardableResult
    func clearEverything() throws -> Int {
        undoHistory.clear()
        let ids = try modelContext.fetch(FetchDescriptor<ClipboardItem>()).map(\.id)
        try deleteItems(ids: ids, reason: .clear)
        try modelContext.fetch(FetchDescriptor<Pinboard>()).forEach(modelContext.delete)
        try saveOrRollback()
        linkPreviews.deleteAll()
        lastItemStore.clear()
        ExceptionRecorder.clear(in: AppPaths.supportDirectory)
        AppDefaults.store.removeObject(forKey: SearchHistory.defaultsKey)
        do {
            try keyRotator()
        } catch {
            Self.privacyLogger
                .error("Clear Everything could not replace the key: \(error.localizedDescription, privacy: .public)")
        }
        return ids.count
    }
}
