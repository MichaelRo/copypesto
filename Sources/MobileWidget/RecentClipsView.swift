// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import WidgetKit

/// The widget on the theme's ground: the latest clip filling a small widget (one link for the whole of it), or rows
/// of clips, each a link to copy it; "No clips yet" for an empty history, "Open Pesto to show your clips" when
/// there is no snapshot to show.
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
        let content = WidgetContent(
            snapshot: entry.snapshot, size: resolvedSize, accessibilityText: typeSize.isAccessibilitySize
        )
        let palette = WidgetPalette(theme: content.theme, isDark: colorScheme == .dark)
        let small = resolvedSize == .small
        let swatch = small ? content.clips.first?.colorHex.flatMap(WidgetPalette.color) : nil
        Group {
            switch content.state {
            case .unavailable:
                WidgetMessage(
                    symbol: "doc.on.clipboard", title: "Open Pesto to show your clips", detail: nil, compact: small
                )
            case .empty:
                WidgetMessage(
                    symbol: "doc.on.clipboard", title: "No clips yet",
                    detail: "Copy something, and it shows up here.", compact: small
                )
            case .clips:
                if small, let clip = content.clips.first {
                    WidgetSmallClip(clip: clip, now: entry.date, palette: palette)
                        .widgetURL(WidgetLink.url(for: clip.id))
                } else {
                    WidgetClipList(
                        clips: content.clips,
                        now: entry.date,
                        palette: palette,
                        roomy: resolvedSize == .large
                    )
                }
            }
        }
        .tint(palette.accent)
        .containerBackground(for: .widget) { swatch ?? palette.ground }
    }
}
