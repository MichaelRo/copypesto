// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Which clips the widget snapshot holds (ADR 0052): the newest clips, and the newest pinned ones, of any kind that
/// `ShortcutClipSearch.isOfferedOutsidePesto` allows, within `WidgetSnapshotPolicy`, each reduced to what a widget
/// draws and, for a short text, its whole text for an in-place copy.
public enum WidgetSnapshotSelection {
    /// How a clip's parts are read: asked only of clips that may be shown, and a thumbnail or a whole text only while
    /// the snapshot has room for it.
    public struct Reader {
        public var source: (ClipboardItem) -> String?
        public var thumbnail: (ClipboardItem) -> Data?
        public var fullText: (ClipboardItem) -> String?

        public init(
            source: @escaping (ClipboardItem) -> String?, thumbnail: @escaping (ClipboardItem) -> Data? = { _ in nil },
            fullText: @escaping (ClipboardItem) -> String? = { _ in nil }
        ) {
            self.source = source
            self.thumbnail = thumbnail
            self.fullText = fullText
        }
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
        source: @escaping (ClipboardItem) -> String?
    ) throws
    -> WidgetSnapshot {
        var newest = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        newest.fetchLimit = WidgetSnapshotPolicy.scanLimit
        var pinned = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        pinned.fetchLimit = WidgetSnapshotPolicy.scanLimit
        let earlier = (previous.map { $0.clips + $0.pinned } ?? []).compactMap { clip in
            clip.thumbnail.map { (clip.id, $0) }
        }
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
            }
        )
        let lists = try lists(newest: context.fetch(newest), pinned: context.fetch(pinned), reader: reader)
        return WidgetSnapshot(createdAt: now, theme: theme, clips: lists.clips, pinned: lists.pinned)
    }

    /// Both lists come newest first. The newest clips are chosen first, so they have the first claim on the room for
    /// thumbnails and whole texts; a pinned clip already chosen is reused rather than read twice.
    public static func lists(newest: [ClipboardItem], pinned: [ClipboardItem], reader: Reader)
    -> (clips: [WidgetClip], pinned: [WidgetClip]) {
        var budget = Budget()
        let clips = choose(from: newest, limit: WidgetSnapshotPolicy.maxClips, reader: reader, budget: &budget)
        let chosen = Dictionary(clips.map { ($0.id, $0) }) { first, _ in first }
        var pins: [WidgetClip] = []
        for item in pinned where pins.count < WidgetSnapshotPolicy.maxPinned && item.isPinned && isEligible(item) {
            if let known = chosen[item.id] {
                pins.append(known)
            } else {
                pins.append(clip(for: item, reader: reader, budget: &budget))
            }
        }
        return (clips, pins)
    }

    /// The newest clips only, as `lists` chooses them.
    public static func clips(from newest: [ClipboardItem], reader: Reader) -> [WidgetClip] {
        lists(newest: newest, pinned: [], reader: reader).clips
    }

    public static func isEligible(_ item: ClipboardItem) -> Bool {
        ShortcutClipSearch.isOfferedOutsidePesto(item)
    }

    private static func choose(from items: [ClipboardItem], limit: Int, reader: Reader, budget: inout Budget)
    -> [WidgetClip] {
        var chosen: [WidgetClip] = []
        for item in items where chosen.count < limit && isEligible(item) {
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
