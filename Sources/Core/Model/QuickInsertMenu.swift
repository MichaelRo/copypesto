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
        /// Set for a collection the person chose (ADR 0062), whose name titles the group.
        public let collection: QuickInsertCollection?
        public let entries: [QuickInsertEntry]

        public var id: String {
            collection.map { "collection:\($0.id.uuidString)" } ?? "section:\(section.rawValue)"
        }

        init(section: QuickInsertEntry.Section, collection: QuickInsertCollection? = nil, entries: [QuickInsertEntry]) {
            self.section = section
            self.collection = collection
            self.entries = entries
        }
    }

    public let state: State
    private let entries: [QuickInsertEntry]
    private let collections: [QuickInsertCollection]

    public init(set: QuickInsertSet?) {
        let activeSet = (set?.autoFillEnabled == true) ? set : nil
        entries = (activeSet?.entries ?? []).filter { $0.kind != .image }
        collections = activeSet?.collections ?? []
        state = activeSet == nil ? .unavailable : entries.isEmpty ? .empty : .ready
    }

    /// Pinned, Snippets and Recent, then each chosen collection under its name; a group with no match is left out.
    public func groups(matching query: String) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ entry: QuickInsertEntry) -> Bool {
            needle.isEmpty || [entry.title, entry.text].contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        let found = entries.filter(matches)
        let sections: [QuickInsertEntry.Section] = [.pinned, .snippets, .recent]
        let byID = Dictionary(entries.map { ($0.id, $0) }) { first, _ in first }
        return sections.compactMap { section in
            let inSection = found.filter { $0.section == section }
            return inSection.isEmpty ? nil : Group(section: section, entries: inSection)
        } + collections.compactMap { collection in
            let members = collection.entryIDs.compactMap { byID[$0] }.filter(matches)
            return members.isEmpty ? nil : Group(section: .collection, collection: collection, entries: members)
        }
    }
}
