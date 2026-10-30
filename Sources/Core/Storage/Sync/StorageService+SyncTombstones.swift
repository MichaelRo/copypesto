// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData

extension StorageService {
    /// The tombstone for a clip the person deleted. With sync on it also carries the plain SHA-256 of the text (read
    /// before the clip and its blob go) and a stamp, so another Mac removes its own copy of the same text too.
    func syncTombstone(for item: ClipboardItem) -> DeletedItemTombstone {
        let tombstone = DeletedItemTombstone(id: item.id)
        guard let clock = SyncJournal.clock(for: modelContainer) else { return tombstone }
        tombstone.kindRaw = "item"
        tombstone.plainHash = item.blob?.decryptedData().map { Data(SHA256.hash(data: $0)).hexString }
        tombstone.changeClock = clock.next().encoded
        tombstone.syncDirty = true
        return tombstone
    }

    func syncCollectionTombstone(id: UUID) -> DeletedItemTombstone {
        let tombstone = DeletedItemTombstone(id: id)
        guard let clock = SyncJournal.clock(for: modelContainer) else { return tombstone }
        tombstone.kindRaw = "collection"
        tombstone.changeClock = clock.next().encoded
        tombstone.syncDirty = true
        return tombstone
    }
}
