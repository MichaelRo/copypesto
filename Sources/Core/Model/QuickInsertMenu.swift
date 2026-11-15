// SPDX-License-Identifier: MIT
import Foundation

/// The AutoFill picker's list: the set's clips in their sections, narrowed by a search.
public struct QuickInsertMenu: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// No set, or one that would not open: the feature is off, or Pesto has not written it yet.
        case unavailable
        case empty
        case ready
    }

    public struct Group: Equatable, Identifiable, Sendable {
        public let section: QuickInsertEntry.Section
        public let entries: [QuickInsertEntry]

        public var id: QuickInsertEntry.Section {
            section
        }
    }

    public let state: State
    private let entries: [QuickInsertEntry]

    public init(set: QuickInsertSet?) {
        entries = set?.entries ?? []
        state = set == nil ? .unavailable : entries.isEmpty ? .empty : .ready
    }

    public func groups(matching query: String) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = needle.isEmpty ? entries : entries.filter { entry in
            [entry.title, entry.text].contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        return QuickInsertEntry.Section.allCases.compactMap { section in
            let inSection = found.filter { $0.section == section }
            return inSection.isEmpty ? nil : Group(section: section, entries: inSection)
        }
    }
}
