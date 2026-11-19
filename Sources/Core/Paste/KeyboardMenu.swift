// SPDX-License-Identifier: MIT
import Foundation

/// What Pesto's keyboard shows (ADR 0061). Without Full Access iOS keeps the shared container and the shared Keychain
/// group closed to a keyboard, so the set is not even asked for; the starters are offered in every state.
public struct KeyboardMenu: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case restricted
        /// No set, or one that would not open: Insert from Pesto is off, or Pesto has not written it yet.
        case unavailable
        case empty
        case ready
    }

    public enum Filter: CaseIterable, Identifiable, Sendable {
        case all
        case pinned
        case snippets
        case recent

        public var id: Self {
            self
        }

        public var title: String {
            switch self {
            case .all: String(localized: "All")
            case .pinned: String(localized: "Pinned")
            case .snippets: String(localized: "Snippets")
            case .recent: String(localized: "Recent")
            }
        }

        var section: QuickInsertEntry.Section? {
            switch self {
            case .all: nil
            case .pinned: .pinned
            case .snippets: .snippets
            case .recent: .recent
            }
        }
    }

    public let state: State
    public let starters = KeyboardStarter.allCases
    private let entries: [QuickInsertEntry]

    public init(hasFullAccess: Bool, loadSet: () -> QuickInsertSet?) {
        guard hasFullAccess else {
            state = .restricted
            entries = []
            return
        }
        let set = loadSet()
        let found = set?.entries ?? []
        entries = QuickInsertEntry.Section.allCases.flatMap { section in found.filter { $0.section == section } }
        state = set == nil ? .unavailable : entries.isEmpty ? .empty : .ready
    }

    /// All, then each section that has a clip; nothing when there is at most one section to choose.
    public var filters: [Filter] {
        let present = Filter.allCases.filter { filter in
            filter.section.map { section in entries.contains { $0.section == section } } ?? false
        }
        return present.count > 1 ? [.all] + present : []
    }

    public func entries(for filter: Filter) -> [QuickInsertEntry] {
        guard let section = filter.section else { return entries }
        return entries.filter { $0.section == section }
    }
}
