// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The keyboard's shelf at one size, drawn at its true point size: as many rows of cards as the keyboard shows (two at
/// Medium and Large on an iPhone held upright, one otherwise), cut off at the edge as the real row is. With `showsKeys`
/// it is framed as the keyboard, with its chips above and its keys below, for Pesto's own settings.
struct KeyboardSizePreview: View {
    let size: KeyboardSize
    let entries: [QuickInsertEntry]
    var chipTitles: [String] = [
        String(localized: "All"),
        String(localized: "Pinned"),
        String(localized: "Snippets")
    ]
    let theme: WidgetSnapshot.Theme
    var appIcons: [String: Data] = [:]
    var showsKeys = false
    var picture: (QuickInsertEntry) -> (image: UIImage, backdrop: UIImage?)? = { _ in nil }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    private static let gap: CGFloat = 6

    private var resolvedAccent: Color {
        Color(hex: theme.accent(dark: colorScheme == .dark)) ?? Color.accentColor
    }

    private var resolvedAccentLabel: Color {
        let hex = theme.accent(dark: colorScheme == .dark)
        return Color(hex: ContrastRatio.labelHex(onFill: hex)) ?? .white
    }

    private var surfaceFill: Color {
        Color(hex: theme.ground(dark: colorScheme == .dark))
            ?? Color(uiColor: .secondarySystemGroupedBackground)
    }

    var body: some View {
        let isRegular = sizeClass == .regular
        let rows = KeyboardLayout.rows(size: size, isRegular: isRegular, isLandscape: verticalSizeClass == .compact)
        let card = KeyboardLayout.cardSize(size: size, isRegular: isRegular)
        VStack(alignment: .leading, spacing: Self.gap) {
            if showsKeys { chips }
            // An overlay never sizes its parent: the row starts at the leading edge and runs off the trailing one, as
            // the keyboard's does.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(rows) * card.height + CGFloat(rows - 1) * Self.gap)
                .overlay(alignment: .topLeading) { shelf(rows: rows, card: card) }
                .clipped()
            if showsKeys { keys }
        }
        .padding(showsKeys ? 8 : 0)
        .background {
            if showsKeys {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(surfaceFill)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview of the keyboard at this size"))
    }

    /// Column by column, as the keyboard's `LazyHGrid` fills its rows.
    private func shelf(rows: Int, card: CGSize) -> some View {
        let columns = stride(from: 0, to: entries.count, by: rows).map { Array(entries[$0..<min(
            $0 + rows,
            entries.count
        )]) }
        return HStack(alignment: .top, spacing: Self.gap) {
            ForEach(columns.indices, id: \.self) { index in
                VStack(spacing: Self.gap) {
                    ForEach(columns[index]) { entry in
                        let shown = picture(entry)
                        QuickInsertCardFace(
                            entry: entry, size: card, theme: theme,
                            appIcon: entry.sourceBundleID.flatMap { appIcons[$0] },
                            picture: shown?.image, backdrop: shown?.backdrop
                        )
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var chips: some View {
        let titles = chipTitles.isEmpty ? [String(localized: "All"), String(localized: "Pinned")] : chipTitles
        return HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                        chipPill(title, isSelected: index == 0)
                    }
                }
            }
            .allowsHitTesting(false)
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.08), in: .circle)
        }
        .frame(height: 30)
    }

    private func chipPill(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(isSelected ? resolvedAccentLabel : .primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                isSelected ? resolvedAccent : Color.primary.opacity(0.08),
                in: .capsule
            )
    }

    private var keys: some View {
        HStack(spacing: 6) {
            keyCap(width: 50, isFunction: true) {
                Text(verbatim: "123")
            }
            keyCap(width: nil, isFunction: false) {
                Text("Space")
            }
            keyCap(width: 50, isFunction: true) {
                Image(systemName: "delete.left")
            }
            keyCap(width: 88, isFunction: true) {
                Text("return")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary)
        .frame(height: 40)
    }

    private func keyCap(width: CGFloat?, isFunction: Bool, @ViewBuilder label: () -> some View) -> some View {
        label()
            .frame(maxWidth: width ?? .infinity, maxHeight: .infinity)
            .frame(width: width)
            .background(keyFill(isFunction: isFunction), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func keyFill(isFunction: Bool) -> Color {
        switch (colorScheme == .dark, isFunction) {
        case (true, true): Color.white.opacity(0.14)
        case (true, false): Color.white.opacity(0.24)
        case (false, true): Color.black.opacity(0.10)
        case (false, false): Color(uiColor: .systemBackground)
        }
    }
}
