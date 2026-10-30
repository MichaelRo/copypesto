// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Synchronization

/// Stamps what changed, at the one place every save goes through (`ModelContext.saveOrRollback`). A clip or collection
/// whose synced fields changed gets a new `changeClock` and is marked dirty; a write to anything else (an embedding, a
/// signature, a picture upgraded to GIF) stamps nothing, because it does not change the fingerprint. Off, and for a
/// store that is not enabled, it does nothing at all. A change applied from another Mac is not stamped again.
public enum SyncJournal {
    private static let clocks = Mutex<[ObjectIdentifier: SyncClock]>([:])

    /// True while `StorageService.applySync` writes what another Mac said, so those saves keep the remote stamps.
    @TaskLocal public static var isApplyingRemote = false

    public static func enable(for container: ModelContainer, clock: SyncClock) {
        clocks.withLock { $0[ObjectIdentifier(container)] = clock }
    }

    public static func disable(for container: ModelContainer) {
        clocks.withLock { _ = $0.removeValue(forKey: ObjectIdentifier(container)) }
    }

    public static func clock(for container: ModelContainer) -> SyncClock? {
        clocks.withLock { $0[ObjectIdentifier(container)] }
    }

    static func stamp(in context: ModelContext) {
        guard !isApplyingRemote, let clock = clock(for: context.container) else { return }
        for model in context.insertedModelsArray + context.changedModelsArray {
            if let item = model as? ClipboardItem {
                let fingerprint = item.syncFingerprintValue()
                guard item.syncFingerprint != fingerprint else { continue }
                item.syncFingerprint = fingerprint
                item.changeClock = clock.next().encoded
                item.syncDirty = true
            } else if let board = model as? Pinboard {
                let fingerprint = board.syncFingerprintValue()
                guard board.syncFingerprint != fingerprint else { continue }
                board.syncFingerprint = fingerprint
                board.changeClock = clock.next().encoded
                board.syncDirty = true
            }
        }
    }
}
