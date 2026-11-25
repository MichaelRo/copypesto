// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The four themes as cards, each half light and half dark so its real colors show whichever way the phone is set,
/// with its icon in the corner, as on the Mac (design board 5, 2026-11-25). The selected one has the accent ring.
struct MobileThemeCards: View {
    @Binding var selection: String
    @Environment(\.pestoAccent) private var accent

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                card(theme)
            }
        }
        .padding(.vertical, 4)
    }

    private func card(_ theme: AppTheme) -> some View {
        let isSelected = AppTheme(stored: selection) == theme
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            selection = theme.rawValue
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Color(hex: theme.groundHex(dark: false)) ?? .white
                    (Color(hex: theme.groundHex(dark: true)) ?? .black)
                        .clipShape(DiagonalLowerHalf())
                    Circle()
                        .fill(Color(hex: theme.accentHex(dark: false)) ?? accent)
                        .frame(width: 12, height: 12)
                        .offset(x: -14, y: -12)
                    Circle()
                        .fill(Color(hex: theme.accentHex(dark: true)) ?? accent)
                        .frame(width: 12, height: 12)
                        .offset(x: 14, y: 12)
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(shape)
                .overlay(shape.strokeBorder(
                    isSelected ? accent : Color.primary.opacity(0.14), lineWidth: isSelected ? 2.5 : 0.75
                ))
                Text(verbatim: theme.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: theme.displayName))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct DiagonalLowerHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
