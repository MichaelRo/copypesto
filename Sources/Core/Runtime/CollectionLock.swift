// SPDX-License-Identifier: MIT
import Foundation

/// Which collections are locked on this device and which of them the person has opened since the shelf or the app
/// last closed (ADR 0081). A locked collection's clips show only on its own chip, once opened; they never join All,
/// Pinned, a search across everything or a smart collection, and never leave Pesto.
public struct CollectionLock: Hashable, Sendable {
    public private(set) var locked: Set<UUID>
    public private(set) var opened: Set<UUID>

    public static let none = CollectionLock(locked: [])

    public init(locked: Set<UUID>, opened: Set<UUID> = []) {
        self.locked = locked
        self.opened = opened.intersection(locked)
    }

    public func isLocked(_ collectionID: UUID?) -> Bool {
        collectionID.map(locked.contains) ?? false
    }

    public func isOpen(_ collectionID: UUID) -> Bool {
        opened.contains(collectionID)
    }

    /// Whether a clip of `collectionID` may show in a view scoped to `scope` (nil: All, Pinned, a smart collection).
    public func admits(collectionID: UUID?, in scope: UUID?) -> Bool {
        guard let collectionID, locked.contains(collectionID) else { return true }
        return scope == collectionID && opened.contains(collectionID)
    }

    public func hidesOutside(collectionID: UUID?) -> Bool {
        isLocked(collectionID)
    }

    public mutating func open(_ collectionID: UUID) {
        if locked.contains(collectionID) { opened.insert(collectionID) }
    }

    public mutating func closeAll() {
        opened = []
    }

    public mutating func relock(to ids: Set<UUID>) {
        locked = ids
        opened.formIntersection(ids)
    }
}
