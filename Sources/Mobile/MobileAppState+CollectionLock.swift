// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// Collections locked on this iPhone or iPad (ADR 0081): a setting of the device; locking needs nothing, unlocking,
/// deleting and exporting ask first; the widget and the keyboard set are written again without them.
@MainActor
extension MobileAppState {
    func setCollection(_ id: UUID, locked: Bool) async -> Bool {
        let stored = AppDefaults.store.value(for: Setting.lockedCollections)
        guard LockedCollections.ids(from: stored).contains(id) != locked else { return true }
        if !locked {
            guard await secretReveal.authenticate(reason: String(localized: "unlock a collection")) else {
                return false
            }
        }
        AppDefaults.store.set(LockedCollections.toggle(id, in: stored), forKey: Setting.lockedCollections.name)
        if locked { secretReveal.closeCollection(id) }
        writeQuickInsert()
        await writeWidget()
        return true
    }

    static var deleteLockedReason: String {
        String(localized: "delete a locked collection")
    }

    static var exportLockedReason: String {
        String(localized: "export a locked collection")
    }

    func confirmsLockedCollectionAction(_ id: UUID, reason: String) async -> Bool {
        guard LockedCollections.current().contains(id) else { return true }
        return await secretReveal.authenticate(reason: reason)
    }
}
