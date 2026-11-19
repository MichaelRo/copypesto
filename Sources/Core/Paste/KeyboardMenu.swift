// SPDX-License-Identifier: MIT
import Foundation

/// What Pesto's keyboard shows (ADRs 0061, 0062): chips like the Mac shelf's (Recent, Pinned, Snippets when they have
/// clips, then the collections the person chose) and a search by the word before the caret. Without Full Access iOS
/// keeps the shared container and the shared Keychain group closed to a keyboard, so the set is not even asked for.
public struct KeyboardMenu: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case restricted
        /// No set, or one that would not open: Insert from Pesto is off, or Pesto has not written it yet.
        case unavailable
        case empty
        case ready
    }

    public enum Chip: Hashable, Identifiable, Sendable {
        case recent
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
    }

    public let state: State
    public let chips: [ChipLabel]
    public let returnsAfterInsert: Bool
    private let entries: [QuickInsertEntry]
    private let collections: [QuickInsertCollection]

    public init(hasFullAccess: Bool, loadSet: () -> QuickInsertSet?) {
        guard hasFullAccess else {
            state = .restricted
            chips = []
            returnsAfterInsert = true
            entries = []
            collections = []
            return
        }
        let set = loadSet()
        entries = set?.entries ?? []
        collections = set?.collections ?? []
        returnsAfterInsert = set?.returnsAfterInsert ?? true
        state = set == nil ? .unavailable : entries.isEmpty ? .empty : .ready
        let sections: [ChipLabel] = [
            ChipLabel(chip: .recent, title: String(localized: "Recent"), symbolName: "clock"),
            ChipLabel(chip: .pinned, title: String(localized: "Pinned"), symbolName: "pin"),
            ChipLabel(chip: .snippets, title: String(localized: "Snippets"), symbolName: "text.badge.plus")
        ]
        let found = entries
        let carried = Set(found.map(\.id))
        chips = sections.filter { label in found.contains { Self.section(of: label.chip) == $0.section } }
            + collections.filter { $0.entryIDs.contains(where: carried.contains) }
            .map { ChipLabel(chip: .collection($0.id), title: $0.name, symbolName: $0.symbolName) }
    }

    public func entries(for chip: Chip) -> [QuickInsertEntry] {
        if case let .collection(id) = chip {
            let byID = Dictionary(entries.map { ($0.id, $0) }) { first, _ in first }
            return collections.first { $0.id == id }?.entryIDs.compactMap { byID[$0] } ?? []
        }
        return entries.filter { $0.section == Self.section(of: chip) }
    }

    /// Every clip the set carries, once, that matches `word`: those whose title starts with it first, then those
    /// whose title or text holds it, each in the set's order; case, accents, Hebrew niqqud and final forms are ignored.
    public func entries(matching word: String) -> [QuickInsertEntry] {
        let needle = KeyboardQuery.normalizedForSearch(word)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let leading = entries.filter {
            KeyboardQuery.normalizedForSearch($0.label()).range(of: needle, options: options.union(.anchored)) != nil
        }
        let inside = entries.filter { entry in
            !leading.contains(entry) && [entry.label(), entry.text].contains {
                KeyboardQuery.normalizedForSearch($0).range(of: needle, options: options) != nil
            }
        }
        return leading + inside
    }

    private static func section(of chip: Chip) -> QuickInsertEntry.Section {
        switch chip {
        case .recent: .recent
        case .pinned: .pinned
        case .snippets: .snippets
        case .collection: .collection
        }
    }
}
