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
        case locked
        case empty
        case ready
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
    public let chips: [ChipLabel]
    public let returnsAfterInsert: Bool
    public let accent: WidgetSnapshot.Theme
    public let keyboardSize: KeyboardSize
    public let setCreatedAt: Date?
    private let entries: [QuickInsertEntry]
    private let collections: [QuickInsertCollection]

    public init(hasFullAccess: Bool, loadSet: () -> QuickInsertSet?) {
        self.init(hasFullAccess: hasFullAccess, now: .now, loadSet: loadSet)
    }

    public init(hasFullAccess: Bool, now: Date, loadSet: () -> QuickInsertSet?) {
        guard hasFullAccess else {
            state = .restricted
            chips = []
            returnsAfterInsert = true
            accent = .brand
            keyboardSize = .medium
            setCreatedAt = nil
            entries = []
            collections = []
            return
        }
        let set = loadSet()
        let activeSet = (set?.keyboardEnabled == true) ? set : nil
        let isExpired = activeSet?.expiresAt.map { now >= $0 } ?? false
        let isLocked = activeSet?.isLocked == true || isExpired
        entries = isLocked ? [] : (activeSet?.entries ?? []).filter {
            !$0.expandsOnInsert || TemplateExpander.fillsWithoutAsking($0.text)
        }
        collections = isLocked ? [] : (activeSet?.collections ?? [])
        returnsAfterInsert = activeSet?.returnsAfterInsert ?? true
        accent = activeSet?.accent ?? .brand
        keyboardSize = activeSet?.keyboardSize ?? .medium
        setCreatedAt = activeSet?.createdAt
        if activeSet == nil {
            state = .unavailable
        } else if isLocked {
            state = .locked
        } else if entries.isEmpty {
            state = .empty
        } else {
            state = .ready
        }
        let sections: [ChipLabel] = [
            ChipLabel(chip: .pinned, title: String(localized: "Pinned"), symbolName: "pin"),
            ChipLabel(chip: .snippets, title: String(localized: "Snippets"), symbolName: "text.badge.plus")
        ]
        let found = entries
        let carried = Set(found.map(\.id))
        let allChip = found.isEmpty ? [] : [
            ChipLabel(chip: .all, title: String(localized: "All"), symbolName: "tray.full")
        ]
        chips = allChip
            + sections.filter { label in found.contains { Self.section(of: label.chip) == $0.section } }
            + collections.filter { $0.entryIDs.contains(where: carried.contains) }
            .map { ChipLabel(chip: .collection($0.id), title: $0.name, symbolName: $0.symbolName, color: $0.color) }
    }

    public func entries(for chip: Chip) -> [QuickInsertEntry] {
        switch chip {
        case .all:
            var seen = Set<UUID>()
            let pinnedFirst = entries.filter {
                ($0.section == .pinned || $0.section == .snippets) && seen.insert($0.id).inserted
            }
            let byID = Dictionary(entries.map { ($0.id, $0) }) { first, _ in first }
            let collectionEntries = collections.flatMap { $0.entryIDs.compactMap { byID[$0] } }
            let remaining = (entries + collectionEntries)
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.date > $1.date }
            return pinnedFirst + remaining
        case .pinned, .snippets:
            guard let section = Self.section(of: chip) else { return [] }
            return entries.filter { $0.section == section }
        case let .collection(id):
            let byID = Dictionary(entries.map { ($0.id, $0) }) { first, _ in first }
            return collections.first { $0.id == id }?.entryIDs.compactMap { byID[$0] } ?? []
        }
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
            !leading.contains(entry) && [entry.label(), entry.text, entry.recognizedText]
                .compactMap(\.self)
                .contains { KeyboardQuery.normalizedForSearch($0).range(of: needle, options: options) != nil }
        }
        return leading + inside
    }

    private static func section(of chip: Chip) -> QuickInsertEntry.Section? {
        switch chip {
        case .pinned: .pinned
        case .snippets: .snippets
        case .all, .collection: nil
        }
    }
}
