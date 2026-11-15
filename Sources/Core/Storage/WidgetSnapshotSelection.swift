// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

/// Which clips the widget snapshot holds (ADR 0052): the newest clips of any kind that
/// `ShortcutClipSearch.isOfferedOutsidePesto` allows, within `WidgetSnapshotPolicy`, each reduced to what a widget
/// draws. A clip's text comes from its preview, never its whole content.
public enum WidgetSnapshotSelection {
    /// `previous` lends its thumbnails to the same clips, so a rewrite decodes only pictures that are new to it. Reads
    /// with the given context, so it runs wherever that context belongs.
    public static func snapshot(
        in context: ModelContext, now: Date, theme: WidgetSnapshot.Theme, previous: WidgetSnapshot? = nil,
        source: (ClipboardItem) -> String?
    ) throws
    -> WidgetSnapshot {
        var descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = WidgetSnapshotPolicy.scanLimit
        let thumbnails = (previous?.clips ?? []).compactMap { clip in clip.thumbnail.map { (clip.id, $0) } }
        let kept = Dictionary(thumbnails) { first, _ in first }
        let clips = try clips(from: context.fetch(descriptor), source: source) { item in
            kept[item.id] ?? item.blob?.decryptedData().flatMap {
                ImageDownsampler.thumbnailJPEG(
                    from: $0, maxPixel: WidgetSnapshotPolicy.thumbnailMaxPixel,
                    maxBytes: WidgetSnapshotPolicy.maxThumbnailBytes
                )
            }
        }
        return WidgetSnapshot(createdAt: now, theme: theme, clips: clips)
    }

    /// `newest` comes newest first; `thumbnail` is asked only of pictures that may be shown, while there is room.
    public static func clips(
        from newest: [ClipboardItem], source: (ClipboardItem) -> String?, thumbnail: (ClipboardItem) -> Data?
    )
    -> [WidgetClip] {
        var budget = WidgetSnapshotPolicy.maxThumbnailTotalBytes
        var chosen: [WidgetClip] = []
        for item in newest where chosen.count < WidgetSnapshotPolicy.maxClips && isEligible(item) {
            var picture: Data?
            if item.type == .image, budget > 0, let made = thumbnail(item),
               made.count <= WidgetSnapshotPolicy.maxThumbnailBytes, made.count <= budget
            {
                picture = made
                budget -= made.count
            }
            chosen.append(clip(for: item, source: source(item), thumbnail: picture))
        }
        return chosen
    }

    public static func isEligible(_ item: ClipboardItem) -> Bool {
        ShortcutClipSearch.isOfferedOutsidePesto(item)
    }

    private static func clip(for item: ClipboardItem, source: String?, thumbnail: Data?) -> WidgetClip {
        let preview = item.displayPreviewText
        let link = item.type == .url ? LinkDisplay.parse(preview) : nil
        let shown = item.type == .file ? URL(fileURLWithPath: preview).lastPathComponent : preview
        return WidgetClip(
            id: item.id, kind: item.type, text: cut(shown, WidgetSnapshotPolicy.maxPreviewCharacters),
            linkHost: link.map { cut($0.host, WidgetSnapshotPolicy.maxLinkPartCharacters) },
            linkPath: link.flatMap { $0.rest.isEmpty ? nil : cut($0.rest, WidgetSnapshotPolicy.maxLinkPartCharacters) },
            colorHex: colorHex(of: item, preview: preview),
            source: source.flatMap { $0.isEmpty ? nil : cut($0, WidgetSnapshotPolicy.maxSourceCharacters) },
            date: item.timestamp, isPinned: item.isPinned, thumbnail: thumbnail
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
