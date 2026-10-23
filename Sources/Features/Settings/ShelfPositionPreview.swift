// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// A miniature desktop with the shelf where the choice puts it: resting on the Dock, or hanging from the menu bar
/// under the notch. The menu bar, notch and Dock are the same in both tiles, so only the shelf moves.
struct ShelfPositionPreview: View {
    @Environment(\.pestoAccent) private var accent
    let position: ShelfPosition
    let themeRaw: String
    var darkThemeRaw = ""

    private static let menuBarHeight: CGFloat = 7
    private static let shelfHeight: CGFloat = 24
    private static let shelfInset: CGFloat = 6
    private static let dockClearance: CGFloat = 12
    private static let shelfRadius: CGFloat = 7

    private var shelfShape: UnevenRoundedRectangle {
        let radius = Self.shelfRadius
        return position == .bottom
            ? UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
            : UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
    }

    var body: some View {
        BrandBackdropView()
            .overlay(alignment: .top) { menuBar }
            .overlay(alignment: .bottom) { dock }
            .overlay(alignment: position == .bottom ? .bottom : .top) {
                shelf
                    .padding(.horizontal, Self.shelfInset)
                    .padding(
                        position == .bottom ? .bottom : .top,
                        position == .bottom ? Self.dockClearance : Self.menuBarHeight
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(5)
            .accessibilityHidden(true)
    }

    private var menuBar: some View {
        Rectangle()
            .fill(.regularMaterial)
            .frame(height: Self.menuBarHeight)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5) }
            .overlay {
                UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 18, height: Self.menuBarHeight)
            }
    }

    private var dock: some View {
        Capsule()
            .fill(.regularMaterial)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .frame(width: 48, height: 6)
            .padding(.bottom, 3)
    }

    private var shelf: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
                    .overlay(alignment: .topLeading) {
                        Circle().fill(accent).frame(width: 3, height: 3).padding(2)
                    }
                    .overlay {
                        if index == 1 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(accent, lineWidth: 1)
                        }
                    }
            }
        }
        .padding(4)
        .frame(height: Self.shelfHeight)
        .background(
            shelfShape.fill(.regularMaterial)
                .overlay { ThemeTintLayer(themeRaw: themeRaw, darkThemeRaw: darkThemeRaw).clipShape(shelfShape) }
        )
        .overlay(shelfShape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
        .shadow(color: accent.opacity(0.35), radius: 5)
    }
}
