// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Synchronization

/// Stamps what changed, at the one place every save goes through (`ModelContext.saveOrRollback`). A clip or collection
/// whose synced fields changed gets a new `changeClock` and is marked dirty; a write to anything else (an embedding, a
/// signature, a picture upgraded to GIF) stamps nothing, because it does not change the fingerprint. Off, and for a
/// store that is not enabled, it does nothing at all. A change applied from another Mac is not stamped again.
public enum SyncJournal {
    /// A container is found by its identity, and the entry holds it weakly: once it is freed, a new container at the
    /// same address must not inherit its clock (and so start stamping and holding clips back by accident).
    private struct Entry {
        weak var container: ModelContainer?
        let clock: SyncClock
    }

    private static let clocks = Mutex<[ObjectIdentifier: Entry]>([:])

    /// True while `StorageService.applySync` writes what another Mac said, so those saves keep the remote stamps.
    @TaskLocal public static var isApplyingRemote = false

    public static func enable(for container: ModelContainer, clock: SyncClock) {
        clocks.withLock { $0[ObjectIdentifier(container)] = Entry(container: container, clock: clock) }
    }

    public static func disable(for container: ModelContainer) {
        clocks.withLock { _ = $0.removeValue(forKey: ObjectIdentifier(container)) }
    }

    public static func clock(for container: ModelContainer) -> SyncClock? {
        clocks.withLock { entries in
            guard let entry = entries[ObjectIdentifier(container)] else { return nil }
            guard entry.container === container else {
                entries.removeValue(forKey: ObjectIdentifier(container))
                return nil
            }
            return entry.clock
        }
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
