// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// The widget on the theme's ground: Pesto cards, one filling a small widget, a row of them in a medium one and a grid
/// in a large one, each doing what "When a Clip Is Tapped" says; "No clips yet" for an empty list, "Open Pesto to
/// show your clips" when there is no snapshot to show.
struct RecentClipsView: View {
    let entry: RecentClipsEntry
    /// Set by a test, which has no widget family in its environment.
    var size: WidgetSize?
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var resolvedSize: WidgetSize {
        if let size { return size }
        return switch family {
        case .systemSmall: .small
        case .systemLarge, .systemExtraLarge: .large
        default: .medium
        }
    }

    var body: some View {
        let accessible = typeSize.isAccessibilitySize
        let content = WidgetContent(
            snapshot: entry.snapshot, size: resolvedSize, source: entry.source, accessibilityText: accessible
        )
        let palette = WidgetPalette(theme: content.theme, isDark: colorScheme == .dark)
        let single = resolvedSize == .small ? content.clips.first : nil
        Group {
            switch content.state {
            case .unavailable:
                WidgetMessage(
                    symbol: "doc.on.clipboard", title: "Open Pesto to show your clips", detail: nil,
                    compact: resolvedSize == .small
                )
            case .empty:
                WidgetMessage(
                    symbol: entry.source == .pinned ? "pin" : "doc.on.clipboard",
                    title: entry.source == .pinned ? "No pinned clips yet" : "No clips yet",
                    detail: entry.source == .pinned
                        ? "Pin a clip in Pesto, and it shows up here." : "Copy something, and it shows up here.",
                    compact: resolvedSize == .small
                )
            case .clips:
                if let single {
                    WidgetTapArea(tap: tap(for: single), isWholeWidget: true) {
                        WidgetCardTile(
                            clip: single, now: entry.date, palette: palette, copied: entry.copiedID == single.id,
                            isWholeWidget: true
                        )
                        .accessibilityHint(WidgetClipSpeech.hint(tap(for: single), kind: single.kind))
                    }
                } else {
                    grid(content.clips, columns: resolvedSize.columns(accessibilityText: accessible), palette: palette)
                }
            }
        }
        .tint(palette.accent)
        .containerBackground(for: .widget) { Self.ground(single: single, palette: palette) }
    }

    private func grid(_ clips: [WidgetClip], columns: Int, palette: WidgetPalette) -> some View {
        let rows = stride(from: 0, to: clips.count, by: columns)
            .map { Array(clips[$0..<min($0 + columns, clips.count)]) }
        return VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    ForEach(rows[index]) { clip in
                        WidgetTapArea(tap: tap(for: clip), isWholeWidget: false) {
                            WidgetCardTile(
                                clip: clip, now: entry.date, palette: palette, copied: entry.copiedID == clip.id,
                                isRoomy: resolvedSize == .large && columns == 2
                            )
                            .accessibilityHint(WidgetClipSpeech.hint(tap(for: clip), kind: clip.kind))
                        }
                    }
                    if rows[index].count < columns {
                        ForEach(rows[index].count..<columns, id: \.self) { _ in Color.clear }
                    }
                }
            }
            if rows.count < 2, resolvedSize == .large { Spacer(minLength: 0) }
        }
    }

    private func tap(for clip: WidgetClip) -> WidgetTap {
        WidgetTap.decide(for: clip, action: entry.tapAction, copiesInPlace: CopyClipIntent.copiesInPlace)
    }

    /// What the widget stands on: the theme's ground, or for a small widget its one card (the color, the picture or
    /// the card's white).
    @ViewBuilder
    static func ground(single: WidgetClip?, palette: WidgetPalette) -> some View {
        if let single, let hex = single.colorHex, let color = WidgetPalette.color(hex) {
            color
        } else if let single, single.kind == .image {
            ZStack {
                WidgetPicture(data: single.thumbnail).privacySensitive()
                WidgetCardTile.scrim
            }
        } else if single != nil {
            ZStack {
                palette.ground
                palette.card
            }
        } else {
            palette.ground
        }
    }
}
