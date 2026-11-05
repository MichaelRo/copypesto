// SPDX-License-Identifier: MIT
import Foundation

/// How long a closed shelf remembers its collection and filters. A quick reopen continues where the person was; after a
/// while the shelf opens on All, as a launcher returns to its root once you have been away.
public enum ShelfContextPolicy {
    public static let memory: TimeInterval = 90

    public static func shouldReset(closedAt: Date?, now: Date) -> Bool {
        guard let closedAt else { return false }
        return now.timeIntervalSince(closedAt) >= memory
    }
}
