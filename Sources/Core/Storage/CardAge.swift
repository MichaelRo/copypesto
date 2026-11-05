// SPDX-License-Identifier: MIT
import Foundation

/// The age under a card's title. In the history it follows use; in a collection it follows the first copy, the same
/// date the collection orders by, so a paste does not change it (ADR 0021).
public enum CardAge {
    public static func interval(for item: ClipboardItem, inCollection: Bool, now: Date = .now) -> TimeInterval {
        now.timeIntervalSince(inCollection ? item.copiedAt : item.timestamp)
    }

    public static func text(for item: ClipboardItem, inCollection: Bool, now: Date = .now) -> String {
        text(interval: interval(for: item, inCollection: inCollection, now: now))
    }

    public static func text(interval: TimeInterval) -> String {
        switch interval {
        case ..<60: "just now"
        case 60..<3600: "\(Int(interval / 60))m ago"
        case 3600..<86_400: "\(Int(interval / 3600))h ago"
        default: "\(Int(interval / 86_400))d ago"
        }
    }
}
