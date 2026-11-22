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

        public init(
            text: @escaping (ClipboardItem) -> String?,
            thumbnail: @escaping (ClipboardItem) -> Data? = { _ in nil },
            recognizedText: @escaping (ClipboardItem) -> String? = { _ in nil },
            source: @escaping (ClipboardItem) -> (name: String?, isThisDevice: Bool) = {
                QuickInsertSelection.defaultSource(for: $0)
            },
            isAnimated: @escaping (ClipboardItem) -> Bool = {
                $0.blob?.mimeType == "com.compuserve.gif" || $0.blob?.mimeType == "public.gif"
            }
        ) {
            self.text = text
            self.thumbnail = thumbnail
            self.recognizedText = recognizedText
            self.source = source
            self.isAnimated = isAnimated
        }
    }

    /// What the person chose in iOS Settings for the keyboard and AutoFill (ADR 0062).
    public struct Options: Equatable, Sendable {
        public var collectionIDs: [UUID]
        public var returnsAfterInsert: Bool
        public var keyboardSize: KeyboardSize
        public var accent: WidgetSnapshot.Theme
        public var keyboardEnabled: Bool
        public var autoFillEnabled: Bool

        public init(
            collectionIDs: [UUID] = [], returnsAfterInsert: Bool = true,
            keyboardSize: KeyboardSize = .medium, accent: WidgetSnapshot.Theme = .brand,
            keyboardEnabled: Bool = true, autoFillEnabled: Bool = true
        ) {
            self.collectionIDs = collectionIDs
            self.returnsAfterInsert = returnsAfterInsert
            self.keyboardSize = keyboardSize
            self.accent = accent
            self.keyboardEnabled = keyboardEnabled
            self.autoFillEnabled = autoFillEnabled
        }

        /// As the settings hold them: `Setting.keyboardCollections` is ids joined by commas; one that does not read
        /// as an id, or a repeat, is dropped.
        public init(
            storedCollections: String, returnsAfterInsert: Bool,
            keyboardSize: KeyboardSize = .medium, accent: WidgetSnapshot.Theme = .brand,
            keyboardEnabled: Bool = true, autoFillEnabled: Bool = true
        ) {
            var seen: Set<UUID> = []
            collectionIDs = storedCollections.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
                .filter { seen.insert($0).inserted }
            self.returnsAfterInsert = returnsAfterInsert
            self.keyboardSize = keyboardSize
            self.accent = accent
            self.keyboardEnabled = keyboardEnabled
            self.autoFillEnabled = autoFillEnabled
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

    @MainActor
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
        let chosen = try members(of: options.collectionIDs, in: context)
        let lists = try lists(
            pinned: context.fetch(pinned), recent: context.fetch(recent), collections: chosen, reader: reader
        )
        return QuickInsertSet(
            createdAt: now, entries: lists.entries, collections: lists.collections,
            returnsAfterInsert: options.returnsAfterInsert,
            accent: options.accent, keyboardSize: options.keyboardSize,
            keyboardEnabled: options.keyboardEnabled, autoFillEnabled: options.autoFillEnabled
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
        pinned: [ClipboardItem], recent: [ClipboardItem], collections: [Members], reader: Reader
    )
    -> (entries: [QuickInsertEntry], collections: [QuickInsertCollection]) {
        var budget = QuickInsertPolicy.maxTotalBytes
        var pins: [QuickInsertEntry] = []
        var snippets: [QuickInsertEntry] = []
        var latest: [QuickInsertEntry] = []
        var extra: [QuickInsertEntry] = []
        var chosen: Set<UUID> = []
        func entry(_ item: ClipboardItem, section: QuickInsertEntry.Section) -> QuickInsertEntry? {
            guard isEligible(item) else { return nil }
            if item.type == .image {
                let isFull = switch section {
                case .pinned: pins.count >= QuickInsertPolicy.maxPinned
                case .recent: latest.count >= QuickInsertPolicy.maxRecent
                case .snippets, .collection: false
                }
                guard !isFull, let made = makeImageEntry(item, section: section, reader: reader, budget: &budget) else {
                    return nil
                }
                chosen.insert(item.id)
                return made
            }
            guard let body = reader.text(item), !body.isEmpty,
                  body.utf8.count <= QuickInsertPolicy.maxEntryBytes, body.utf8.count <= budget,
                  SensitiveContentDetector.detectAnywhere(in: body) == nil else { return nil }
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
            return makeTextEntry(
                item, body: body, section: isSnippet ? .snippets : section, isSnippet: isSnippet, reader: reader
            )
        }
        for item in pinned where item.collectionID == nil {
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
            carried.append(makeCollection(members.collection, entryIDs: ids))
        }
        return (pins + snippets + latest + extra, carried)
    }

    private static func makeCollection(_ board: Pinboard, entryIDs: [UUID]) -> QuickInsertCollection {
        QuickInsertCollection(
            id: board.id,
            name: String(board.name.prefix(QuickInsertPolicy.maxCollectionNameCharacters)),
            symbolName: String(board.symbolName.prefix(WidgetSnapshotPolicy.maxSymbolNameCharacters)),
            color: String(board.colorHex.prefix(7)),
            entryIDs: entryIDs
        )
    }

    public static func defaultSource(for item: ClipboardItem) -> (name: String?, isThisDevice: Bool) {
        if item.isRemote { return (PasteboardCapture.remoteSourceName, false) }
        if let appName = item.knownSourceAppName { return (appName, false) }
        if item.syncOrigin != nil { return (nil, false) }
        return (nil, true)
    }

    public static func isEligible(_ item: ClipboardItem) -> Bool {
        insertableTypes.contains(item.type) && ShortcutClipSearch.isOfferedOutsidePesto(item)
    }

    private static func trimmedSource(for item: ClipboardItem, reader: Reader) -> (name: String?, isThisDevice: Bool) {
        let src = reader.source(item)
        let clean = src.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (clean.isEmpty ? nil : String(clean.prefix(QuickInsertPolicy.maxSourceCharacters)), src.isThisDevice)
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
                  thumb.count + trimmed.utf8.count <= budget else { return nil }
            return trimmed
        }
        budget -= thumb.count + (ocr?.utf8.count ?? 0)
        let src = trimmedSource(for: item, reader: reader)
        return QuickInsertEntry(
            id: item.id, section: section, kind: .image,
            title: title(of: item, text: ocr ?? ""), text: "",
            expandsOnInsert: false,
            fromAnotherDevice: item.syncOrigin != nil || item.isRemote,
            customTitle: item.customTitle, ogTitle: nil,
            date: item.timestamp, source: src.name, sourceIsThisDevice: src.isThisDevice,
            thumbnail: thumb, recognizedText: ocr, isAnimated: reader.isAnimated(item)
        )
    }

    private static func makeTextEntry(
        _ item: ClipboardItem, body: String, section: QuickInsertEntry.Section, isSnippet: Bool, reader: Reader
    )
    -> QuickInsertEntry {
        let src = trimmedSource(for: item, reader: reader)
        return QuickInsertEntry(
            id: item.id, section: section, kind: item.type,
            title: title(of: item, text: body), text: body,
            expandsOnInsert: isSnippet,
            fromAnotherDevice: item.syncOrigin != nil || item.isRemote,
            customTitle: item.customTitle, ogTitle: item.ogTitle,
            date: item.timestamp, source: src.name, sourceIsThisDevice: src.isThisDevice
        )
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
