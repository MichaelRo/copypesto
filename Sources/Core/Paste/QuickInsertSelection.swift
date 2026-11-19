// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Which clips the quick-insert set holds (ADR 0051): pinned clips, then snippets that need nothing from the person,
/// then the newest text, each newest first, within `QuickInsertPolicy`. Only text a field can take (text, code, a
/// link as its address, a color as its value), and only what `ShortcutClipSearch.isOfferedOutsidePesto` allows.
public enum QuickInsertSelection {
    private static let insertableTypes: Set<ClipboardType> = [.text, .code, .url, .color]

    /// What the person chose in iOS Settings for the keyboard and AutoFill (ADR 0062).
    public struct Options: Equatable, Sendable {
        public var collectionIDs: [UUID]
        public var returnsAfterInsert: Bool

        public init(collectionIDs: [UUID] = [], returnsAfterInsert: Bool = true) {
            self.collectionIDs = collectionIDs
            self.returnsAfterInsert = returnsAfterInsert
        }

        /// As the settings hold them: `Setting.keyboardCollections` is ids joined by commas; one that does not read
        /// as an id, or a repeat, is dropped.
        public init(storedCollections: String, returnsAfterInsert: Bool) {
            var seen: Set<UUID> = []
            collectionIDs = storedCollections.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
                .filter { seen.insert($0).inserted }
            self.returnsAfterInsert = returnsAfterInsert
        }

        public static func stored(_ ids: [UUID]) -> String {
            ids.map(\.uuidString).joined(separator: ",")
        }
    }

    /// A chosen collection and its clips in its own order.
    public struct Members {
        public let collection: Pinboard
        public let items: [ClipboardItem]
    }

    @MainActor
    public static func set(
        in context: ModelContext, now: Date, options: Options = Options(),
        text: (ClipboardItem) -> String? = { $0.blob?.decryptedText() }
    ) throws
        -> QuickInsertSet
    {
        var pinned = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        pinned.fetchLimit = QuickInsertPolicy.scanLimit
        var recent = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recent.fetchLimit = QuickInsertPolicy.scanLimit
        let chosen = try members(of: options.collectionIDs, in: context)
        let lists = try lists(
            pinned: context.fetch(pinned), recent: context.fetch(recent), collections: chosen, text: text
        )
        return QuickInsertSet(
            createdAt: now, entries: lists.entries, collections: lists.collections,
            returnsAfterInsert: options.returnsAfterInsert
        )
    }

    /// The chosen collections that still exist, in the person's order, at most `maxCollections`: a plain one's newest
    /// members as `CollectionOrder` lists them, a smart one's matches among the newest clips.
    public static func members(of ids: [UUID], in context: ModelContext) throws -> [Members] {
        var window: [ClipboardItem]?
        var found: [Members] = []
        for id in ids where found.count < QuickInsertPolicy.maxCollections {
            var board = FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == id })
            board.fetchLimit = 1
            guard let collection = try context.fetch(board).first else { continue }
            let items: [ClipboardItem]
            if collection.isSmart {
                if window == nil {
                    var newest = FetchDescriptor<ClipboardItem>(
                        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                    )
                    newest.fetchLimit = WidgetSnapshotPolicy.smartScanLimit
                    window = try context.fetch(newest)
                }
                items = WidgetSnapshotSelection.smartMatches(
                    of: collection, in: window ?? [], limit: QuickInsertPolicy.maxCollectionClips
                )
            } else {
                var newest = FetchDescriptor<ClipboardItem>(
                    predicate: #Predicate { $0.collectionID == id },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                newest.fetchLimit = WidgetSnapshotPolicy.collectionScanLimit
                items = try CollectionOrder.sorted(context.fetch(newest))
            }
            found.append(Members(collection: collection, items: items))
        }
        return found
    }

    /// `pinned` and `recent` come newest first; `text` opens a clip's whole text, and is asked only of clips that
    /// may be offered.
    public static func entries(
        pinned: [ClipboardItem], recent: [ClipboardItem], text: (ClipboardItem) -> String?
    )
    -> [QuickInsertEntry] {
        lists(pinned: pinned, recent: recent, collections: [], text: text).entries
    }

    /// Pinned, snippets and recent clips first, then each chosen collection's: a clip already chosen is listed by the
    /// collection rather than carried twice, and all of it shares one size budget.
    public static func lists(
        pinned: [ClipboardItem], recent: [ClipboardItem], collections: [Members], text: (ClipboardItem) -> String?
    )
    -> (entries: [QuickInsertEntry], collections: [QuickInsertCollection]) {
        var budget = QuickInsertPolicy.maxTotalBytes
        var pins: [QuickInsertEntry] = []
        var snippets: [QuickInsertEntry] = []
        var latest: [QuickInsertEntry] = []
        var extra: [QuickInsertEntry] = []
        var chosen: Set<UUID> = []
        func entry(_ item: ClipboardItem, section: QuickInsertEntry.Section) -> QuickInsertEntry? {
            guard isEligible(item), let body = text(item), !body.isEmpty,
                  body.utf8.count <= QuickInsertPolicy.maxEntryBytes, body.utf8.count <= budget else { return nil }
            // A pinned clip with placeholders is a snippet wherever it is listed: one that asks for a value never
            // comes in, and a collection never carries one the snippets section turned away.
            if item.isPinned, TemplateExpander.containsPlaceholders(body), section != .pinned { return nil }
            let isSnippet = section == .pinned && TemplateExpander.containsPlaceholders(body)
            let isFull = switch section {
            case .pinned: isSnippet ? snippets.count >= QuickInsertPolicy.maxSnippets
                : pins.count >= QuickInsertPolicy.maxPinned
            case .recent: latest.count >= QuickInsertPolicy.maxRecent
            case .snippets, .collection: false
            }
            guard !isFull, !isSnippet || TemplateExpander.fillsWithoutAsking(body) else { return nil }
            budget -= body.utf8.count
            chosen.insert(item.id)
            return QuickInsertEntry(
                id: item.id, section: isSnippet ? .snippets : section, kind: item.type,
                title: title(of: item, text: body), text: body,
                expandsOnInsert: isSnippet,
                fromAnotherDevice: item.syncOrigin != nil || item.isRemote
            )
        }
        for item in pinned {
            guard let made = entry(item, section: .pinned) else { continue }
            if made.section == .snippets { snippets.append(made) } else { pins.append(made) }
        }
        for item in recent {
            if let made = entry(item, section: .recent) { latest.append(made) }
        }
        var carried: [QuickInsertCollection] = []
        for members in collections {
            var ids: [UUID] = []
            for item in members.items where ids.count < QuickInsertPolicy.maxCollectionClips {
                guard !ids.contains(item.id) else { continue }
                if chosen.contains(item.id) {
                    ids.append(item.id)
                } else if let made = entry(item, section: .collection) {
                    extra.append(made)
                    ids.append(item.id)
                }
            }
            let board = members.collection
            carried.append(QuickInsertCollection(
                id: board.id, name: String(board.name.prefix(QuickInsertPolicy.maxCollectionNameCharacters)),
                symbolName: String(board.symbolName.prefix(WidgetSnapshotPolicy.maxSymbolNameCharacters)),
                entryIDs: ids
            ))
        }
        return (pins + snippets + latest + extra, carried)
    }

    public static func isEligible(_ item: ClipboardItem) -> Bool {
        insertableTypes.contains(item.type) && ShortcutClipSearch.isOfferedOutsidePesto(item)
    }

    private static func title(of item: ClipboardItem, text: String) -> String {
        let named = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let chosen = named.isEmpty ? line : named
        return String((chosen.isEmpty ? item.type.presentation.label : chosen)
            .prefix(QuickInsertPolicy.maxTitleCharacters))
    }
}
