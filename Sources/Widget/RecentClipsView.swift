// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// The widget on the theme's ground: Pesto cards, one filling a small widget, two side by side in a medium one, two by
/// two in a large one and two by four in an extra large one, with page buttons on medium and large (ADR 0067), each
/// card doing what "When a Clip Is Chosen" says; "No clips yet" for an empty list, "Choose a
/// collection" for a collection the snapshot does not carry (ADR 0060), "Open Pesto to show your clips" when there is
/// no snapshot to show. On the Mac a message opens the shelf, which is also when Pesto
/// asks whether a widget is installed (ADR 0059).
struct RecentClipsView: View {
    let entry: RecentClipsEntry
    /// Set by a test, which has no widget family in its environment.
    var size: WidgetSize?
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var resolvedSize: WidgetSize {
        size ?? WidgetSize(family: family)
    }

    var body: some View {
        let accessible = typeSize.isAccessibilitySize
        let content = WidgetContent(
            snapshot: entry.snapshot, size: resolvedSize, source: entry.source, accessibilityText: accessible,
            page: entry.page
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
                .opensShelfOnTheMac()
            case .locked:
                WidgetMessage(
                    symbol: "lock", title: "Locked", detail: "Open Pesto to see your clips.",
                    compact: resolvedSize == .small
                )
                .opensUnlockOnPhone()
            case .hidden:
                WidgetMessage(
                    symbol: "eye.slash", title: "Clip contents hidden",
                    detail: "They come back when sharing ends or you choose Show Clip Contents.",
                    compact: resolvedSize == .small
                )
                .opensShelfOnTheMac()
            case .noCollection:
                WidgetMessage(
                    symbol: "square.stack", title: "Choose a collection",
                    detail: "Edit the widget to choose the collection it shows.", compact: resolvedSize == .small
                )
                .opensShelfOnTheMac()
            case .empty:
                emptyMessage(content.collection).opensShelfOnTheMac()
            case .clips:
                if let single {
                    WidgetTapArea(tap: tap(for: single), isWholeWidget: true) {
                        WidgetCardTile(
                            clip: single, now: entry.date, palette: palette, copied: entry.copiedID == single.id,
                            isWholeWidget: true, appIcon: appIcon(for: single)
                        )
                        .accessibilityHint(WidgetClipSpeech.hint(tap(for: single), kind: single.kind))
                    }
                } else {
                    paged(content, accessible: accessible, palette: palette)
                }
            }
        }
        .tint(palette.accent)
        .containerBackground(for: .widget) { Self.ground(single: single, palette: palette) }
    }

    @ViewBuilder
    private func paged(_ content: WidgetContent, accessible: Bool, palette: WidgetPalette) -> some View {
        let grid = grid(content.clips, columns: resolvedSize.columns(accessibilityText: accessible), palette: palette)
        if content.pageCount > 1, let snapshot = entry.snapshot {
            let control = WidgetPageControl(
                key: WidgetPaging.key(source: entry.source, size: resolvedSize), page: content.page,
                pageCount: content.pageCount, snapshotCreatedAt: snapshot.createdAt,
                isVertical: resolvedSize == .medium
            )
            if resolvedSize == .medium {
                HStack(spacing: 6) {
                    grid
                    control.frame(width: 28)
                }
            } else {
                VStack(spacing: 4) {
                    grid
                    control.frame(height: 24)
                }
            }
        } else {
            grid
        }
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
                                isRoomy: resolvedSize != .medium && columns > 1, appIcon: appIcon(for: clip)
                            )
                            .accessibilityHint(WidgetClipSpeech.hint(tap(for: clip), kind: clip.kind))
                        }
                    }
                    if rows[index].count < columns {
                        ForEach(rows[index].count..<columns, id: \.self) { _ in Color.clear }
                    }
                }
            }
            if rows.count < resolvedSize.grid(accessibilityText: false).rows { Spacer(minLength: 0) }
        }
    }

    private func appIcon(for clip: WidgetClip) -> Data? {
        clip.sourceBundleID.flatMap { entry.snapshot?.appIcons[$0] }
    }

    private func emptyMessage(_ collection: WidgetCollection?) -> WidgetMessage {
        let compact = resolvedSize == .small
        if let collection {
            return WidgetMessage(
                symbol: collection.symbolName, title: "No clips in this collection yet",
                detail: collection.isSmart
                    ? "Clips that match it show up here." : "Add a clip to it in Pesto, and it shows up here.",
                compact: compact
            )
        }
        if entry.source == .pinned {
            return WidgetMessage(
                symbol: "pin", title: "No pinned clips yet", detail: "Pin a clip in Pesto, and it shows up here.",
                compact: compact
            )
        }
        return WidgetMessage(
            symbol: "doc.on.clipboard", title: "No clips yet", detail: "Copy something, and it shows up here.",
            compact: compact
        )
    }

    private func tap(for clip: WidgetClip) -> WidgetTap {
        WidgetTap.decide(for: clip, action: entry.tapAction, copiesInPlace: Self.copiesInPlace)
    }

    #if os(iOS)
    static let copiesInPlace = CopyClipIntent.copiesInPlace
    #else
    static let copiesInPlace = false
    #endif

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
