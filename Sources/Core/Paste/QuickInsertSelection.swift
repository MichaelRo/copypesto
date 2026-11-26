// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Which clips the quick-insert set holds (ADR 0051): pinned clips, then snippets that need nothing from the person,
/// then the newest text, each newest first, within `QuickInsertPolicy`. Only text a field can take (text, code, a
/// link as its address, a color as its value), and only what `ShortcutClipSearch.isOfferedOutsidePesto` allows.
public enum QuickInsertSelection {
    private static let insertableTypes: Set<ClipboardType> = [.text, .code, .url, .color, .image]

    /// How a clip's parts are read: asked only of clips that may be offered, and within the set's size budget.
    public struct Reader {
        public var text: (ClipboardItem) -> String?
        public var thumbnail: (ClipboardItem) -> Data?
        public var recognizedText: (ClipboardItem) -> String?
        public var source: (ClipboardItem) -> (name: String?, isThisDevice: Bool)
        public var isAnimated: (ClipboardItem) -> Bool
        public var fieldMemory: (ClipboardItem) -> [String: String]?

        public init(
            text: @escaping (ClipboardItem) -> String?,
            thumbnail: @escaping (ClipboardItem) -> Data? = { _ in nil },
            recognizedText: @escaping (ClipboardItem) -> String? = { _ in nil },
            source: @escaping (ClipboardItem) -> (name: String?, isThisDevice: Bool) = {
                QuickInsertSelection.defaultSource(for: $0)
            },
            isAnimated: @escaping (ClipboardItem) -> Bool = {
                $0.blob?.mimeType == "com.compuserve.gif" || $0.blob?.mimeType == "public.gif"
            },
            fieldMemory: @escaping (ClipboardItem) -> [String: String]? = {
                $0.sensitivityRaw == nil ? $0.metadata.fieldMemory : nil
            }
        ) {
            self.text = text
            self.thumbnail = thumbnail
            self.recognizedText = recognizedText
            self.source = source
            self.isAnimated = isAnimated
            self.fieldMemory = fieldMemory
        }
    }

    /// Which collections the quick-insert set carries (ADR 0062).
    public enum CollectionMode: Equatable, Sendable {
        case all
        case custom([UUID])
    }

    /// What the person chose in iOS Settings for the keyboard and AutoFill (ADR 0062).
    public struct Options: Equatable, Sendable {
        public var collectionMode: CollectionMode
        public var hiddenCollectionIDs: Set<UUID>
        public var returnsAfterInsert: Bool
        public var keyboardSize: KeyboardSize
        public var accent: WidgetSnapshot.Theme
        public var keyboardEnabled: Bool
        public var autoFillEnabled: Bool
        public var rememberFillIns: Bool

        public var collectionIDs: [UUID] {
            if case let .custom(ids) = collectionMode { return ids }
            return []
        }

        public init(
            collectionIDs: [UUID] = [],
            collectionMode: CollectionMode? = nil,
            hiddenCollectionIDs: Set<UUID> = [],
            returnsAfterInsert: Bool = true,
            keyboardSize: KeyboardSize = .medium,
            accent: WidgetSnapshot.Theme = .brand,
            keyboardEnabled: Bool = true,
            autoFillEnabled: Bool = true,
            rememberFillIns: Bool = true
        ) {
            self.collectionMode = collectionMode ?? .custom(collectionIDs)
            self.hiddenCollectionIDs = hiddenCollectionIDs
            self.returnsAfterInsert = returnsAfterInsert
            self.keyboardSize = keyboardSize
            self.accent = accent
            self.keyboardEnabled = keyboardEnabled
            self.autoFillEnabled = autoFillEnabled
            self.rememberFillIns = rememberFillIns
        }

        /// As the settings hold them: `Setting.keyboardCollections` is `*` for all eligible collections, or ids
        /// joined by commas; one that does not read as an id, or a repeat, is dropped.
        public init(
            storedCollections: String,
            hiddenCollectionIDs: Set<UUID> = [],
            returnsAfterInsert: Bool,
            keyboardSize: KeyboardSize = .medium,
            accent: WidgetSnapshot.Theme = .brand,
            keyboardEnabled: Bool = true,
            autoFillEnabled: Bool = true,
            rememberFillIns: Bool = true
        ) {
            let trimmed = storedCollections.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == QuickInsertPolicy.allCollectionsToken {
                collectionMode = .all
            } else {
                var seen: Set<UUID> = []
                let ids = trimmed.split(separator: ",").compactMap {
                    UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines))
                }.filter { seen.insert($0).inserted }
                collectionMode = .custom(ids)
            }
            self.hiddenCollectionIDs = hiddenCollectionIDs
            self.returnsAfterInsert = returnsAfterInsert
            self.keyboardSize = keyboardSize
            self.accent = accent
            self.keyboardEnabled = keyboardEnabled
            self.autoFillEnabled = autoFillEnabled
            self.rememberFillIns = rememberFillIns
        }

        public static func stored(_ ids: [UUID]) -> String {
            ids.map(\.uuidString).joined(separator: ",")
        }

        /// Resolves eligible collections in display order, filtering out the auto-created `Snippets` smart collection,
        /// mobile-hidden collections, and bounding to `QuickInsertPolicy.maxCollections`.
        public func resolvedCollections(from boards: [Pinboard]) -> [Pinboard] {
            let eligible: [Pinboard] = switch collectionMode {
            case .all:
                boards
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .filter { !$0.isSnippetsSmartCollection && !hiddenCollectionIDs.contains($0.id) }
            case let .custom(ids):
                ids.compactMap { id in
                    boards.first { $0.id == id && !hiddenCollectionIDs.contains($0.id) }
                }
            }
            return Array(eligible.prefix(QuickInsertPolicy.maxCollections))
        }
    }

    /// A chosen collection and its clips in its own order.
    public struct Members {
        public let collection: Pinboard
        public let items: [ClipboardItem]
    }

    public static func set(
        in context: ModelContext, now: Date, options: Options = Options(),
        recognizedTexts: RecognizedTextStore = RecognizedTextStore(),
        source: ((ClipboardItem) -> (name: String?, isThisDevice: Bool))? = nil,
        text: @escaping (ClipboardItem) -> String? = { $0.blob?.decryptedText() }
    ) throws
        -> QuickInsertSet
    {
        let reader = Reader(
            text: text,
            thumbnail: { $0.quickInsertThumbnailData() },
            recognizedText: { item in
                RecognizedText.text(of: item, store: recognizedTexts)
            },
            source: source ?? { defaultSource(for: $0) }
        )
        return try set(in: context, now: now, options: options, reader: reader)
    }

    public static func set(
        in context: ModelContext, now: Date, options: Options = Options(), reader: Reader
    ) throws
        -> QuickInsertSet
    {
        var pinned = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned && $0.collectionID == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        pinned.fetchLimit = QuickInsertPolicy.scanLimit
        var recent = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        recent.fetchLimit = QuickInsertPolicy.scanLimit
        let chosen = try members(of: options, in: context)
        let lists = try lists(
            pinned: context.fetch(pinned), recent: context.fetch(recent), collections: chosen, reader: reader,
            rememberFillIns: options.rememberFillIns
        )
        return QuickInsertSet(
            createdAt: now, entries: lists.entries, collections: lists.collections,
            returnsAfterInsert: options.returnsAfterInsert,
            accent: options.accent, keyboardSize: options.keyboardSize,
            keyboardEnabled: options.keyboardEnabled, autoFillEnabled: options.autoFillEnabled
        )
    }

    public static func members(of options: Options, in context: ModelContext) throws -> [Members] {
        let boards = try context.fetch(FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.sortOrder)]))
        return try members(ofBoards: options.resolvedCollections(from: boards), in: context)
    }

    /// The chosen collections that still exist, in the person's order, at most `maxCollections`: a plain one's newest
    /// members as `CollectionOrder` lists them, a smart one's matches among the newest clips.
    public static func members(of ids: [UUID], in context: ModelContext) throws -> [Members] {
        let boards = try context.fetch(FetchDescriptor<Pinboard>())
        return try members(ofBoards: Options(collectionIDs: ids).resolvedCollections(from: boards), in: context)
    }

    private static func members(ofBoards boards: [Pinboard], in context: ModelContext) throws -> [Members] {
        var window: [ClipboardItem]?
        var found: [Members] = []
        for collection in boards.prefix(QuickInsertPolicy.maxCollections) {
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
                let id = collection.id
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
        withoutActuallyEscaping(text) { escapingText in
            lists(pinned: pinned, recent: recent, collections: [], text: escapingText).entries
        }
    }

    /// Pinned, snippets and recent clips first, then each chosen collection's: a clip already chosen is listed by the
    /// collection rather than carried twice, and all of it shares one size budget.
    public static func lists(
        pinned: [ClipboardItem], recent: [ClipboardItem], collections: [Members],
        text: @escaping (ClipboardItem) -> String?
    )
    -> (entries: [QuickInsertEntry], collections: [QuickInsertCollection]) {
        lists(pinned: pinned, recent: recent, collections: collections, reader: Reader(text: text))
    }

    public static func lists(
        pinned: [ClipboardItem], recent: [ClipboardItem], collections: [Members], reader: Reader,
        rememberFillIns: Bool = true
    )
    -> (entries: [QuickInsertEntry], collections: [QuickInsertCollection]) {
        var budget = QuickInsertPolicy.maxTotalBytes
        var pins: [QuickInsertEntry] = []
        var snippets: [QuickInsertEntry] = []
        var latest: [QuickInsertEntry] = []
        var chosen: Set<UUID> = []
        func entry(_ item: ClipboardItem, section: QuickInsertEntry.Section) -> QuickInsertEntry? {
            guard isEligible(item) else { return nil }
            if item.type == .image {
                guard !isFullSection(section, pins: pins.count, snippets: snippets.count, latest: latest.count),
                      let made = makeImageEntry(item, section: section, reader: reader, budget: &budget) else
                {
                    return nil
                }
                chosen.insert(item.id)
                return made
            }
            guard let body = reader.text(item), !body.isEmpty,
                  body.utf8.count <= QuickInsertPolicy.maxEntryBytes else { return nil }
            let cost = EncodedText.bytes(body)
            guard cost <= budget, SensitiveContentDetector.detectAnywhere(in: body) == nil else { return nil }
            let isSnippet = item.isPinned && TemplateExpander.containsPlaceholders(body)
            let targetSection: QuickInsertEntry.Section = (section == .pinned && isSnippet) ? .snippets : section
            guard !isFullSection(targetSection, pins: pins.count, snippets: snippets.count, latest: latest.count),
                  !isSnippet || TemplateExpander.fillsWithoutSystemContext(body) else { return nil }
            budget -= cost
            chosen.insert(item.id)
            let memory = isSnippet
                ? safeFieldMemory(
                    for: item,
                    body: body,
                    rememberFillIns: rememberFillIns,
                    reader: reader,
                    budget: &budget
                )
                : nil
            return makeTextEntry(
                item,
                draft: TextEntryDraft(
                    body: body, section: targetSection, isSnippet: isSnippet, fieldMemory: memory
                ),
                reader: reader
            )
        }
        for item in pinned where item.collectionID == nil {
            guard let made = entry(item, section: .pinned) else { continue }
            if made.section == .snippets { snippets.append(made) } else { pins.append(made) }
        }
        for item in recent {
            if let made = entry(item, section: .recent) { latest.append(made) }
        }
        let (extra, carried) = collectCollections(
            collections, chosen: chosen, makeEntry: { entry($0, section: .collection) }
        )
        return (pins + snippets + latest + extra, carried)
    }
}

private extension QuickInsertSelection {
    static func isFullSection(_ section: QuickInsertEntry.Section, pins: Int, snippets: Int, latest: Int) -> Bool {
        switch section {
        case .pinned: pins >= QuickInsertPolicy.maxPinned
        case .snippets: snippets >= QuickInsertPolicy.maxSnippets
        case .recent: latest >= QuickInsertPolicy.maxRecent
        case .collection: false
        }
    }

    static func collectCollections(
        _ collections: [Members],
        chosen: Set<UUID>,
        makeEntry: (ClipboardItem) -> QuickInsertEntry?
    )
    -> (extra: [QuickInsertEntry], carried: [QuickInsertCollection]) {
        var extra: [QuickInsertEntry] = []
        var carried: [QuickInsertCollection] = []
        for members in collections {
            var ids: [UUID] = []
            for item in members.items where ids.count < QuickInsertPolicy.maxCollectionClips {
                guard !ids.contains(item.id) else { continue }
                if chosen.contains(item.id) {
                    ids.append(item.id)
                } else if let made = makeEntry(item) {
                    extra.append(made)
                    ids.append(item.id)
                }
            }
            carried.append(makeCollection(members.collection, entryIDs: ids))
        }
        return (extra, carried)
    }

    private static func makeCollection(_ board: Pinboard, entryIDs: [UUID]) -> QuickInsertCollection {
        QuickInsertCollection(
            id: board.id,
            name: EncodedText.prefix(board.name, maxCharacters: QuickInsertPolicy.maxCollectionNameCharacters),
            symbolName: EncodedText.prefix(
                board.symbolName,
                maxCharacters: WidgetSnapshotPolicy.maxSymbolNameCharacters
            ),
            color: EncodedText.prefix(board.colorHex, maxCharacters: 7),
            entryIDs: entryIDs
        )
    }

    private static func trimmedSource(for item: ClipboardItem, reader: Reader) -> (name: String?, isThisDevice: Bool) {
        let src = reader.source(item)
        let clean = src.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = EncodedText.prefix(clean, maxCharacters: QuickInsertPolicy.maxSourceCharacters)
        return (name.isEmpty ? nil : name, src.isThisDevice)
    }

    private static func makeImageEntry(
        _ item: ClipboardItem, section: QuickInsertEntry.Section, reader: Reader, budget: inout Int
    )
    -> QuickInsertEntry? {
        guard SensitiveContentDetector.detectAnywhere(in: item.displayPreviewText) == nil else { return nil }
        let rawOCR = reader.recognizedText(item)
        if let rawOCR, SensitiveContentDetector.detectAnywhere(in: rawOCR) != nil { return nil }
        guard let thumb = reader.thumbnail(item), !thumb.isEmpty,
              thumb.count <= QuickInsertPolicy.maxThumbnailBytes, thumb.count <= budget else { return nil }
        let ocr: String? = rawOCR.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.utf8.count <= QuickInsertPolicy.maxEntryBytes,
                  thumb.count + EncodedText.bytes(trimmed) <= budget else { return nil }
            return trimmed
        }
        budget -= thumb.count + (ocr.map(EncodedText.bytes) ?? 0)
        let src = trimmedSource(for: item, reader: reader)
        return QuickInsertEntry(
            id: item.id, section: section, kind: .image,
            title: title(of: item, text: ocr ?? ""), text: "",
            expandsOnInsert: false,
            fromAnotherDevice: item.syncOrigin != nil || item.isRemote,
            customTitle: boundedTitle(item.customTitle), ogTitle: nil,
            date: item.timestamp, source: src.name, sourceIsThisDevice: src.isThisDevice,
            thumbnail: thumb, recognizedText: ocr, isAnimated: reader.isAnimated(item)
        )
    }

    static func safeFieldMemory(
        for item: ClipboardItem,
        body: String,
        rememberFillIns: Bool,
        reader: Reader,
        budget: inout Int
    )
    -> [String: String]? {
        guard rememberFillIns, item.sensitivityRaw == nil,
              let raw = reader.fieldMemory(item), !raw.isEmpty else { return nil }
        let validKeys = Set(FillInParser.fields(in: body).map(\.label))
        guard !validKeys.isEmpty else { return nil }
        var kept: [String: String] = [:]
        var used = 0
        for (key, value) in raw.sorted(by: { $0.key < $1.key }) {
            guard validKeys.contains(key), !value.isEmpty,
                  value.utf8.count <= 1024,
                  SensitiveContentDetector.detectAnywhere(in: key) == nil,
                  SensitiveContentDetector.detectAnywhere(in: value) == nil else { continue }
            let pairBytes = EncodedText.bytes(key) + EncodedText.bytes(value)
            guard used + pairBytes <= 2048, pairBytes <= budget else { break }
            kept[key] = value
            used += pairBytes
            budget -= pairBytes
        }
        return kept.isEmpty ? nil : kept
    }

    struct TextEntryDraft {
        let body: String
        let section: QuickInsertEntry.Section
        let isSnippet: Bool
        let fieldMemory: [String: String]?
    }

    static func makeTextEntry(
        _ item: ClipboardItem, draft: TextEntryDraft, reader: Reader
    )
    -> QuickInsertEntry {
        let src = trimmedSource(for: item, reader: reader)
        return QuickInsertEntry(
            id: item.id, section: draft.section, kind: item.type,
            title: title(of: item, text: draft.body), text: draft.body,
            expandsOnInsert: draft.isSnippet,
            fromAnotherDevice: item.syncOrigin != nil || item.isRemote,
            customTitle: boundedTitle(item.customTitle), ogTitle: boundedTitle(item.ogTitle),
            date: item.timestamp, source: src.name, sourceIsThisDevice: src.isThisDevice,
            fieldMemory: draft.fieldMemory
        )
    }

    static func title(of item: ClipboardItem, text: String) -> String {
        let named = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let line = text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let chosen = named.isEmpty ? line : named
        return boundedTitle(chosen) ?? item.type.presentation.label
    }

    static func boundedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let cut = EncodedText.prefix(title, maxCharacters: QuickInsertPolicy.maxTitleCharacters)
        return cut.isEmpty ? nil : cut
    }
}

public extension QuickInsertSelection {
    static func defaultSource(for item: ClipboardItem) -> (name: String?, isThisDevice: Bool) {
        if item.isRemote { return (PasteboardCapture.remoteSourceName, false) }
        if let appName = item.knownSourceAppName { return (appName, false) }
        if item.syncOrigin != nil { return (nil, false) }
        return (nil, true)
    }

    static func isEligible(_ item: ClipboardItem) -> Bool {
        insertableTypes.contains(item.type) && ShortcutClipSearch.isOfferedOutsidePesto(item)
    }
}
