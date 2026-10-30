// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

extension StorageService {
    /// Marks for sending again, with the stamps they already have, everything whose latest change this Mac wrote: its
    /// clips, collections and the deletions it made in the last year. A snapshot of this Mac's log is made of these, so
    /// the older segments can go. What other Macs wrote stays in their logs.
    @discardableResult
    func markOwnForSnapshot(deviceID: String, tombstoneAge: TimeInterval = 365 * 86_400, now: Date = .now) async throws
    -> Int {
        var count = 0
        func mine(_ encoded: String?) -> Bool {
            encoded.flatMap(SyncStamp.init(encoded:))?.deviceID == deviceID
        }
        try await forEachClip { item in
            guard mine(item.changeClock) else { return }
            item.syncDirty = true
            count += 1
        }
        for board in try modelContext.fetch(FetchDescriptor<Pinboard>()) where mine(board.changeClock) {
            board.syncDirty = true
            count += 1
        }
        let oldest = now.addingTimeInterval(-tombstoneAge)
        for row in try modelContext.fetch(FetchDescriptor<DeletedItemTombstone>()) where mine(row.changeClock) {
            guard row.deletedAt > oldest else { continue }
            row.syncDirty = true
            count += 1
        }
        try saveOrRollback()
        return count
    }
}
