// SPDX-License-Identifier: MIT
import Foundation

/// The AutoFill picker's list: the set's clips in their sections, narrowed by a search.
public struct QuickInsertMenu: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// No set, or one that would not open: the feature is off, or Pesto has not written it yet.
        case unavailable
        case locked
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
        self.init(set: set, now: .now)
    }

    public init(set: QuickInsertSet?, now: Date) {
        let activeSet = (set?.autoFillEnabled == true) ? set : nil
        let isExpired = activeSet?.expiresAt.map { now >= $0 } ?? false
        let isLocked = activeSet?.isLocked == true || isExpired
        accent = set?.accent
        let loadedEntries = isLocked ? [] : (activeSet?.entries ?? []).filter { $0.kind != .image }
        let loadedCollections = isLocked ? [] : (activeSet?.collections ?? [])
        entries = loadedEntries
        collections = loadedCollections
        if activeSet == nil {
            state = .unavailable
        } else if isLocked {
            state = .locked
        } else if loadedEntries.isEmpty {
            state = .empty
        } else {
            state = .ready
        }
        let sectionChips: [ChipLabel] = [
            ChipLabel(chip: .pinned, title: String(localized: "Pinned"), symbolName: "pin"),
            ChipLabel(chip: .snippets, title: String(localized: "Snippets"), symbolName: "text.badge.plus")
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

    /// Pinned clips first, then all remaining clips newest-first in a single flat group; or a single chip's group.
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
            var seen = Set<UUID>()
            let pinnedFirst = found.filter {
                ($0.section == .pinned || $0.section == .snippets) && seen.insert($0.id).inserted
            }
            let collectionEntries = collections.flatMap { collection in
                collection.entryIDs.compactMap { byID[$0] }.filter(matches)
            }
            let remaining = (found + collectionEntries)
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.date > $1.date }
            let ordered = pinnedFirst + remaining
            return ordered.isEmpty ? [] : [Group(section: .pinned, entries: ordered)]
        case .pinned, .snippets:
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
        case .all, .collection: nil
        }
    }
}
