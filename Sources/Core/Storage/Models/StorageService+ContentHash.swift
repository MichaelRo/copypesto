// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Replaces every plain SHA-256 fingerprint with its keyed form. It needs only the old hash, not the content, so
    /// no clip is decrypted, and the result equals what a fresh copy of the same content would store, so duplicates
    /// are still found. Idempotent. Returns how many items changed.
    @discardableResult
    func migrateContentHashes() async throws -> Int {
        guard let key = try? encryption.loadOrCreateKey() else { return 0 }
        let prefix = ContentHash.prefix
        var changed = 0
        try await forEachClip(matching: FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.contentHash.starts(with: prefix) }
        )) { item in
            guard let keyed = ContentHash.migrated(legacy: item.contentHash, key: key) else { return }
            item.contentHash = keyed
            changed += 1
        }
        return changed
    }
}
