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
    let theme: WidgetSnapshot.Theme
    var appIcons: [String: Data] = [:]
    var showsKeys = false
    var picture: (QuickInsertEntry) -> (image: UIImage, backdrop: UIImage?)? = { _ in nil }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private static let gap: CGFloat = 6

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
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray5))
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
        HStack(spacing: 6) {
            stub(width: 52)
            stub(width: 68)
            stub(width: 60)
            Spacer(minLength: 0)
            Circle().fill(Color(.systemBackground)).frame(width: 30, height: 30)
        }
        .frame(height: 30)
    }

    private var keys: some View {
        HStack(spacing: 6) {
            key(width: 50, isFunction: true)
            key(width: nil, isFunction: false)
            key(width: 50, isFunction: true)
            key(width: 88, isFunction: true)
        }
        .frame(height: 42)
    }

    private func stub(width: CGFloat) -> some View {
        Capsule().fill(Color(.systemBackground).opacity(0.7)).frame(width: width, height: 30)
    }

    private func key(width: CGFloat?, isFunction: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isFunction ? Color(.systemGray3) : Color(.systemBackground))
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}
