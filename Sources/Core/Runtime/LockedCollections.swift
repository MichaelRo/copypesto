// SPDX-License-Identifier: MIT
import Foundation

/// The collections locked on this device (ADR 0081), as `Setting.lockedCollections` stores them.
public enum LockedCollections {
    public static func ids(from stored: String) -> Set<UUID> {
        Set(stored.split(separator: ",").compactMap {
            UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }

    public static func encode(_ ids: Set<UUID>) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    public static func toggle(_ id: UUID, in stored: String) -> String {
        var current = ids(from: stored)
        if current.remove(id) == nil { current.insert(id) }
        return encode(current)
    }

    public static func current(from store: UserDefaults = AppDefaults.store) -> Set<UUID> {
        ids(from: store.value(for: Setting.lockedCollections))
    }
}
