// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Which clips the widget snapshot holds (ADR 0052, 0060): the newest clips, the newest pinned ones and the clips of
/// the first collections, of any kind that `ShortcutClipSearch.isOfferedOutsidePesto` allows, within
/// `WidgetSnapshotPolicy`, each reduced to what a widget draws and, for a short text, its whole text for an in-place
/// copy.
public enum WidgetSnapshotSelection {
    /// How a clip's parts are read: asked only of clips that may be shown, and a thumbnail or a whole text only while
    /// the snapshot has room for it.
    public struct Reader {
        public var source: (ClipboardItem) -> String?
        public var thumbnail: (ClipboardItem) -> Data?
        public var fullText: (ClipboardItem) -> String?
        public var recognizedText: (ClipboardItem) -> String?

        public init(
            source: @escaping (ClipboardItem) -> String?, thumbnail: @escaping (ClipboardItem) -> Data? = { _ in nil },
            fullText: @escaping (ClipboardItem) -> String? = { _ in nil },
            recognizedText: @escaping (ClipboardItem) -> String? = { _ in nil }
        ) {
            self.source = source
            self.thumbnail = thumbnail
            self.fullText = fullText
            self.recognizedText = recognizedText
        }
    }

    /// A collection and the clips it lists, in its order, before eligibility and the bounds are applied.
    public struct Members {
        public let collection: WidgetCollection
        public let items: [ClipboardItem]

        public init(collection: WidgetCollection, items: [ClipboardItem]) {
            self.collection = collection
            self.items = items
        }
    }

    public struct Lists {
        public let clips: [WidgetClip]
        public let pinned: [WidgetClip]
        public let collections: [WidgetCollection]
        public let collectionClipIDs: [UUID: [UUID]]
        public let collectionClips: [WidgetClip]
    }

    private struct Budget {
        var thumbnails = WidgetSnapshotPolicy.maxThumbnailTotalBytes
        var fullTexts = WidgetSnapshotPolicy.maxFullTextTotalBytes
    }

    private static let copyableKinds: Set<ClipboardType> = [.text, .code, .url, .color]

    /// `previous` lends its thumbnails to the same clips, so a rewrite decodes only pictures that are new to it. Reads
    /// with the given context, so it runs wherever that context belongs.
    public static func snapshot(
        in context: ModelContext, now: Date, theme: WidgetSnapshot.Theme, previous: WidgetSnapshot? = nil,
        recognizedTexts: RecognizedTextStore = RecognizedTextStore(),
        source: @escaping (ClipboardItem) -> String?
    ) throws
    -> WidgetSnapshot {
        let earlier = (previous?.allClips ?? []).compactMap { clip in clip.thumbnail.map { (clip.id, $0) } }
        let kept = Dictionary(earlier) { first, _ in first }
        let reader = Reader(
            source: source,
            thumbnail: { item in
                kept[item.id] ?? item.blob?.decryptedData().flatMap {
                    ImageDownsampler.thumbnailJPEG(
                        from: $0, maxPixel: WidgetSnapshotPolicy.thumbnailMaxPixel,
                        maxBytes: WidgetSnapshotPolicy.maxThumbnailBytes
                    )
                }
            },
            fullText: { item in
                item.byteSize <= WidgetSnapshotPolicy.maxFullTextBytes ? item.blob?.decryptedText() : nil
            },
            recognizedText: { item in
                item.type == .image && recognizedTexts.exists(for: item.id) ? recognizedTexts.load(for: item.id) : nil
            }
        )
        return try snapshot(in: context, now: now, theme: theme, reader: reader)
    }

    public static func snapshot(in context: ModelContext, now: Date, theme: WidgetSnapshot.Theme, reader: Reader) throws
    -> WidgetSnapshot {
        var newest = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        newest.fetchLimit = WidgetSnapshotPolicy.scanLimit
        var pinned = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        pinned.fetchLimit = WidgetSnapshotPolicy.scanLimit
        let lists = try lists(
            newest: context.fetch(newest), pinned: context.fetch(pinned), collections: members(in: context),
            reader: reader
        )
        return WidgetSnapshot(
            createdAt: now, theme: theme, clips: lists.clips, pinned: lists.pinned, collections: lists.collections,
            collectionClipIDs: lists.collectionClipIDs, collectionClips: lists.collectionClips
        )
    }

    /// The first collections by `sortOrder` (as Pesto's own lists sort them), each with the clips that may be shown, in
    /// its order: a plain collection's newest `collectionScanLimit` members as `CollectionOrder` lists them, a smart
    /// one's matches among the newest `smartScanLimit` clips, newest first.
    public static func members(in context: ModelContext) throws -> [Members] {
        var boards = FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.sortOrder)])
        boards.fetchLimit = WidgetSnapshotPolicy.maxCollections
        let collections = try context.fetch(boards)
        var window: [ClipboardItem]?
        var members: [Members] = []
        for board in collections {
            let items: [ClipboardItem]
            if board.isSmart {
                if window == nil {
                    var newest = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
                    newest.fetchLimit = WidgetSnapshotPolicy.smartScanLimit
                    window = try context.fetch(newest)
                }
                items = smartMatches(of: board, in: window ?? [], limit: WidgetSnapshotPolicy.maxClips)
            } else {
                let id = board.id
                var newest = FetchDescriptor<ClipboardItem>(
                    predicate: #Predicate { $0.collectionID == id },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                newest.fetchLimit = WidgetSnapshotPolicy.collectionScanLimit
                let window = try context.fetch(newest).filter(isEligible)
                items = Array(CollectionOrder.sorted(window).prefix(WidgetSnapshotPolicy.maxClips))
            }
            members.append(Members(collection: widgetCollection(board), items: items))
        }
        return members
    }

    /// The lists come newest first and each collection in its own order. The newest clips are chosen first, then the
    /// pinned ones, then the collections', so they claim the room for thumbnails and whole texts in that order; a
    /// clip already chosen is reused rather than read twice.
    public static func lists(
        newest: [ClipboardItem], pinned: [ClipboardItem], collections: [Members] = [], reader: Reader
    )
    -> Lists {
        var budget = Budget()
        let clips = choose(from: newest, limit: WidgetSnapshotPolicy.maxClips, reader: reader, budget: &budget)
        var chosen = Dictionary(clips.map { ($0.id, $0) }) { first, _ in first }
        var pins: [WidgetClip] = []
        for item in pinned where pins.count < WidgetSnapshotPolicy.maxPinned && item.isPinned && mayInclude(
            item,
            reader: reader
        ) {
            if let known = chosen[item.id] {
                pins.append(known)
            } else {
                let made = clip(for: item, reader: reader, budget: &budget)
                chosen[item.id] = made
                pins.append(made)
            }
        }
        var ids: [UUID: [UUID]] = [:]
        var extra: [WidgetClip] = []
        for members in collections.prefix(WidgetSnapshotPolicy.maxCollections) {
            var listed: [UUID] = []
            for item in members.items where listed.count < WidgetSnapshotPolicy.maxClips && mayInclude(
                item,
                reader: reader
            ) {
                guard !listed.contains(item.id) else { continue }
                if chosen[item.id] == nil {
                    let made = clip(for: item, reader: reader, budget: &budget)
                    chosen[item.id] = made
                    extra.append(made)
                }
                listed.append(item.id)
            }
            ids[members.collection.id] = listed
        }
        return Lists(
            clips: clips, pinned: pins, collections: collections.prefix(WidgetSnapshotPolicy.maxCollections)
                .map(\.collection), collectionClipIDs: ids, collectionClips: extra
        )
    }

    /// The newest clips only, as `lists` chooses them.
    public static func clips(from newest: [ClipboardItem], reader: Reader) -> [WidgetClip] {
        lists(newest: newest, pinned: [], reader: reader).clips
    }

    public static func isEligible(_ item: ClipboardItem) -> Bool {
        ShortcutClipSearch.isOfferedOutsidePesto(item)
    }

    private static func mayInclude(_ item: ClipboardItem, reader: Reader) -> Bool {
        guard isEligible(item) else { return false }
        guard item.type == .image else { return true }
        if SensitiveContentDetector.detectAnywhere(in: item.displayPreviewText) != nil {
            return false
        }
        if let ocr = reader.recognizedText(item), SensitiveContentDetector.detectAnywhere(in: ocr) != nil {
            return false
        }
        return true
    }

    /// A smart collection whose rules do not decode or compile shows nothing, as it does in Pesto.
    static func smartMatches(of board: Pinboard, in window: [ClipboardItem], limit: Int) -> [ClipboardItem] {
        guard let data = board.smartPredicateData, let rules = try? SmartCollectionPredicate.decodeRuleSet(data),
              SmartCollectionPredicate.canCompileRuleSet(rules) else { return [] }
        var matches: [ClipboardItem] = []
        for item in window where matches.count < limit && isEligible(item) {
            if rules.matches(item) { matches.append(item) }
        }
        return matches
    }

    private static func widgetCollection(_ board: Pinboard) -> WidgetCollection {
        WidgetCollection(
            id: board.id, name: cut(board.name, WidgetSnapshotPolicy.maxCollectionNameCharacters),
            symbolName: cut(board.symbolName, WidgetSnapshotPolicy.maxSymbolNameCharacters),
            colorHex: cut(board.colorHex, 7), isSmart: board.isSmart
        )
    }

    private static func choose(from items: [ClipboardItem], limit: Int, reader: Reader, budget: inout Budget)
    -> [WidgetClip] {
        var chosen: [WidgetClip] = []
        for item in items where chosen.count < limit && mayInclude(item, reader: reader) {
            chosen.append(clip(for: item, reader: reader, budget: &budget))
        }
        return chosen
    }

    private static func clip(for item: ClipboardItem, reader: Reader, budget: inout Budget) -> WidgetClip {
        var picture: Data?
        if item.type == .image, budget.thumbnails > 0, let made = reader.thumbnail(item),
           made.count <= WidgetSnapshotPolicy.maxThumbnailBytes, made.count <= budget.thumbnails
        {
            picture = made
            budget.thumbnails -= made.count
        }
        var whole: String?
        if copyableKinds.contains(item.type), budget.fullTexts > 0, let text = reader.fullText(item), !text.isEmpty,
           text.utf8.count <= WidgetSnapshotPolicy.maxFullTextBytes, text.utf8.count <= budget.fullTexts
        {
            whole = text
            budget.fullTexts -= text.utf8.count
        }
        let preview = item.displayPreviewText
        let link = item.type == .url ? LinkDisplay.parse(preview) : nil
        let shown = item.type == .file ? URL(fileURLWithPath: preview).lastPathComponent : preview
        return WidgetClip(
            id: item.id, kind: item.type, text: cut(shown, WidgetSnapshotPolicy.maxPreviewCharacters),
            fullText: whole,
            linkHost: link.map { cut($0.host, WidgetSnapshotPolicy.maxLinkPartCharacters) },
            linkPath: link.flatMap { $0.rest.isEmpty ? nil : cut($0.rest, WidgetSnapshotPolicy.maxLinkPartCharacters) },
            colorHex: colorHex(of: item, preview: preview),
            source: reader.source(item)
                .flatMap { $0.isEmpty ? nil : cut($0, WidgetSnapshotPolicy.maxSourceCharacters) },
            date: item.timestamp, isPinned: item.isPinned, thumbnail: picture
        )
    }

    /// A color clip's swatch: its stored preview is the color's text, the one preview kept in the clear (ADR 0002).
    private static func colorHex(of item: ClipboardItem, preview: String) -> String? {
        switch item.type {
        case .color: ColorLiteralParser.firstColor(in: preview).map(hex)
        default: nil
        }
    }

    private static func cut(_ text: String, _ limit: Int) -> String {
        String(text.prefix(limit))
    }

    private static func hex(_ color: HexColorComponents) -> String {
        func byte(_ channel: Double) -> Int {
            Int((min(max(channel, 0), 1) * 255).rounded())
        }
        return String(format: "%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }
}
