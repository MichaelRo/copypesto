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

    public enum Chip: Hashable, Identifiable, Sendable {
        case all
        case pinned
        case snippets
        case recent
        case collection(UUID)

        public var id: Self {
            self
        }
    }

    public struct ChipLabel: Equatable, Sendable {
        public let chip: Chip
        public let title: String
        public let symbolName: String
        public let color: String

        public init(chip: Chip, title: String, symbolName: String, color: String = "") {
            self.chip = chip
            self.title = title
            self.symbolName = symbolName
            self.color = color
        }
    }

    public let state: State
    public let accent: WidgetSnapshot.Theme?
    public let chips: [ChipLabel]
    private let entries: [QuickInsertEntry]
    private let collections: [QuickInsertCollection]

    public init(set: QuickInsertSet?) {
        let activeSet = (set?.autoFillEnabled == true) ? set : nil
        accent = set?.accent
        let loadedEntries = (activeSet?.entries ?? []).filter { $0.kind != .image }
        let loadedCollections = activeSet?.collections ?? []
        entries = loadedEntries
        collections = loadedCollections
        state = activeSet == nil ? .unavailable : loadedEntries.isEmpty ? .empty : .ready
        let sectionChips: [ChipLabel] = [
            ChipLabel(chip: .pinned, title: String(localized: "Pinned"), symbolName: "pin"),
            ChipLabel(chip: .snippets, title: String(localized: "Snippets"), symbolName: "text.badge.plus"),
            ChipLabel(chip: .recent, title: String(localized: "Recent"), symbolName: "clock")
        ]
        let carried = Set(loadedEntries.map(\.id))
        let availableSections = sectionChips.filter { label in
            loadedEntries.contains { Self.section(of: label.chip) == $0.section }
        }
        let availableCollections = loadedCollections
            .filter { $0.entryIDs.contains(where: carried.contains) }
            .map { ChipLabel(chip: .collection($0.id), title: $0.name, symbolName: $0.symbolName, color: $0.color) }
        chips = (loadedEntries.isEmpty ? [] : [ChipLabel(
            chip: .all,
            title: String(localized: "All"),
            symbolName: "square.grid.2x2"
        )])
            + availableSections + availableCollections
    }

    /// Pinned, Snippets and Recent, then each chosen collection under its name; a group with no match is left out.
    public func groups(matching query: String, chip: Chip = .all) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ entry: QuickInsertEntry) -> Bool {
            needle.isEmpty || [entry.title, entry.text].contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        let found = entries.filter(matches)
        let byID = Dictionary(entries.map { ($0.id, $0) }) { first, _ in first }
        switch chip {
        case .all:
            let sections: [QuickInsertEntry.Section] = [.pinned, .snippets, .recent]
            return sections.compactMap { section in
                let inSection = found.filter { $0.section == section }
                return inSection.isEmpty ? nil : Group(section: section, entries: inSection)
            } + collections.compactMap { collection in
                let members = collection.entryIDs.compactMap { byID[$0] }.filter(matches)
                return members.isEmpty ? nil : Group(section: .collection, collection: collection, entries: members)
            }
        case .pinned, .snippets, .recent:
            guard let section = Self.section(of: chip) else { return [] }
            let inSection = found.filter { $0.section == section }
            return inSection.isEmpty ? [] : [Group(section: section, entries: inSection)]
        case let .collection(id):
            guard let collection = collections.first(where: { $0.id == id }) else { return [] }
            let members = collection.entryIDs.compactMap { byID[$0] }.filter(matches)
            return members.isEmpty ? [] : [Group(section: .collection, collection: collection, entries: members)]
        }
    }

    private static func section(of chip: Chip) -> QuickInsertEntry.Section? {
        switch chip {
        case .pinned: .pinned
        case .snippets: .snippets
        case .recent: .recent
        case .all, .collection: nil
        }
    }
}
