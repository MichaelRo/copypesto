// SPDX-License-Identifier: MIT
import Foundation

/// Collections hidden from the iPhone horizontal chip bar on this device only, stored in
/// `Setting.hiddenMobileCollections`.
enum HiddenCollections {
    static func ids(from stored: String) -> Set<UUID> {
        Set(
            stored
                .split(separator: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    static func encode(_ ids: Set<UUID>) -> String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    static func toggle(_ id: UUID, in stored: String) -> String {
        var current = ids(from: stored)
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        return encode(current)
    }
}
