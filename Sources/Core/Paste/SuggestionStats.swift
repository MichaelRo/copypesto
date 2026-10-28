// SPDX-License-Identifier: MIT
import Foundation

/// What the shelf's suggestions did on this Mac, from the ledger it already keeps (ADR 0014, ADR 0017). Nothing is sent
/// anywhere; the person may copy the summary into an issue.
public struct SuggestionStats: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let kind: ShelfSuggestionKind
        public let shown: Int
        public let accepted: Int
        public let declined: Int
    }

    public let rows: [Row]

    public init(ledger: SuggestionLedger) {
        rows = ShelfSuggestionKind.allCases.compactMap { kind in
            let counts = ledger.counts(for: kind)
            guard counts.shown > 0 else { return nil }
            return Row(kind: kind, shown: counts.shown, accepted: counts.accepted, declined: counts.declined)
        }
    }

    public func row(for kind: ShelfSuggestionKind) -> Row? {
        rows.first { $0.kind == kind }
    }

    public var summary: String {
        guard !rows.isEmpty else { return "No suggestions shown yet." }
        return rows.map {
            "\(Self.name(of: $0.kind)): shown \($0.shown), accepted \($0.accepted), declined \($0.declined)"
        }.joined(separator: "\n")
    }

    static func name(of kind: ShelfSuggestionKind) -> String {
        switch kind {
        case .shortcutOffer: "Shortcut offers"
        case .shortcutReminder: "Shortcut reminders"
        case .shortcutRelease: "Shortcut releases"
        case .snippet: "Snippets"
        }
    }
}
