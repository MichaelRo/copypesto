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

    /// How long until `text(interval:)` reads differently: the widget's timeline has an entry at each such moment.
    public static func untilNextChange(interval: TimeInterval) -> TimeInterval {
        let elapsed = max(interval, 0)
        let step: TimeInterval = switch elapsed {
        case ..<3600: 60
        case 3600..<86_400: 3600
        default: 86_400
        }
        return step - elapsed.truncatingRemainder(dividingBy: step)
    }

    public static func spoken(interval seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: "just now"
        case 60..<3600: String(localized: "\(Int(seconds / 60)) minutes ago")
        case 3600..<86_400: String(localized: "\(Int(seconds / 3600)) hours ago")
        default: String(localized: "\(Int(seconds / 86_400)) days ago")
        }
    }
}
