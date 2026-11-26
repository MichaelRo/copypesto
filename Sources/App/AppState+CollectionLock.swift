// SPDX-License-Identifier: MIT
import Foundation
import PestoCore

/// Collections locked on this Mac (ADR 0081): the lock is a setting of the device, opening one asks through the one
/// authentication window, and what was opened closes with the shelf, the History Lock or the screen going to sleep.
@MainActor
extension AppState {
    var collectionLock: CollectionLock {
        CollectionLock(locked: LockedCollections.current(), opened: openedLockedCollections)
    }

    /// Whether this clip may be pasted or copied from where the person is: never while its collection is locked and
    /// not opened.
    func isWithheldByCollectionLock(_ item: ClipboardItem) -> Bool {
        let lock = collectionLock
        guard let id = item.collectionID, lock.isLocked(id) else { return false }
        return !lock.isOpen(id)
    }

    func openLockedCollection(_ id: UUID) async -> Bool {
        guard LockedCollections.current().contains(id) else { return true }
        guard await authenticateInShelf(reason: String(localized: "open a locked collection")) else { return false }
        openedLockedCollections.insert(id)
        return true
    }

    /// Locking needs nothing; unlocking asks first, as showing what it hid would.
    func setCollection(_ id: UUID, locked: Bool) async -> Bool {
        let stored = AppDefaults.store.value(for: Setting.lockedCollections)
        guard LockedCollections.ids(from: stored).contains(id) != locked else { return true }
        if !locked {
            guard await authenticateInShelf(reason: String(localized: "unlock a collection")) else { return false }
        }
        AppDefaults.store.set(LockedCollections.toggle(id, in: stored), forKey: Setting.lockedCollections.name)
        if locked {
            openedLockedCollections.remove(id)
            LastItemStore.clear()
        }
        collectionLockChanged?()
        return true
    }

    /// Deleting or exporting a locked collection hands out or ends what it hides, so it asks first. The lock's id
    /// outlives a delete, so Undo brings the collection back locked.
    func confirmsLockedCollectionAction(_ id: UUID, reason: String) async -> Bool {
        guard LockedCollections.current().contains(id) else { return true }
        return await authenticateInShelf(reason: reason)
    }
}
