// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// What sits behind the shelf in website screenshots: the brand palette as a calm gradient the glass can pick up, and
/// for the hero a note window as "the app you were in". Colours are the plan's.
struct MarketingBackdropView: View {
    let style: MarketingBackdropStyle
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Setting.appTheme) private var themeRaw: String

    private var isDark: Bool {
        scheme == .dark
    }

    private var theme: AppTheme {
        AppTheme(stored: themeRaw)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                gradient
                glow(at: UnitPoint(x: 0.18, y: 0.88), radius: proxy.size.width * 0.5, color: lowGlow)
                glow(at: UnitPoint(x: 0.85, y: 0.12), radius: proxy.size.width * 0.35, color: highGlow)
                if style == .hero {
                    leaves(in: proxy.size)
                    hostNote(in: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityIdentifier("marketing-backdrop")
    }

    private var gradient: some View {
        let colors: [String] = switch (theme, isDark) {
        case (.basil, true): ["1E4A33", "16301F", "0E1A14"]
        case (.basil, false): ["C9DFCB", "E4EBD0", "F1E6C4"]
        case (.parmesan, true): ["3A3A22", "2A2B1A", "1B1C12"]
        case (.parmesan, false): ["F1E4B8", "E6D49A", "D9C27E"]
        case (.pineNut, true): ["4A3524", "33261B", "211812"]
        case (.pineNut, false): ["EBCFA3", "DDBB86", "CDA46C"]
        case (.mortar, true): ["1F2A38", "141B25", "0B0F15"]
        case (.mortar, false): ["B7C4D3", "9DAEC2", "8596AE"]
        }
        return LinearGradient(
            stops: [
                .init(color: Color.brand(colors[0]), location: 0),
                .init(color: Color.brand(colors[1]), location: isDark ? 0.6 : 0.55),
                .init(color: Color.brand(colors[2]), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var lowGlow: Color {
        switch (theme, isDark) {
        case (.basil, true): Color.brand("2F7A49").opacity(0.45)
        case (.basil, false): Color.brand("529D6E").opacity(0.22)
        case (.parmesan, true): Color.brand("E3C04A").opacity(0.15)
        case (.parmesan, false): Color.brand("7A5F00").opacity(0.14)
        case (.pineNut, true): Color.brand("E2A15E").opacity(0.15)
        case (.pineNut, false): Color.brand("8A4F16").opacity(0.14)
        case (.mortar, true): Color.brand("B9CDBF").opacity(0.15)
        case (.mortar, false): Color.brand("3F5446").opacity(0.14)
        }
    }

    private var highGlow: Color {
        switch (theme, isDark) {
        case (.basil, true): Color.brand("6DBE85").opacity(0.10)
        case (.basil, false): Color.brand("C9A227").opacity(0.10)
        case (.parmesan, _): Color.brand("E3C04A").opacity(0.10)
        case (.pineNut, _): Color.brand("E2A15E").opacity(0.10)
        case (.mortar, _): Color.brand("B9CDBF").opacity(0.10)
        }
    }

    private func glow(at center: UnitPoint, radius: CGFloat, color: Color) -> some View {
        RadialGradient(colors: [color, color.opacity(0)], center: center, startRadius: 0, endRadius: radius)
    }

    private func leaves(in size: CGSize) -> some View {
        let tint = isDark ? Color.brand("6DBE85").opacity(0.09) : Color.brand("2F7A49").opacity(0.07)
        return ZStack {
            leaf.fill(tint).frame(width: 330, height: 190).rotationEffect(.degrees(20)).offset(x: -90, y: 20)
            leaf.fill(tint).frame(width: 380, height: 220).rotationEffect(.degrees(-26)).offset(x: 60, y: -20)
            leaf.fill(tint).frame(width: 250, height: 150).rotationEffect(.degrees(77)).offset(x: -10, y: -90)
        }
        .position(x: size.width - 360, y: 190)
    }

    private var leaf: some Shape {
        LeafShape()
    }

    /// A plain stand-in for the app you were using (not any real app's window), partly behind the shelf.
    private func hostNote(in size: CGSize) -> some View {
        let ink = isDark ? Color.brand("F6EFD9") : Color.brand("2B2F2A")
        let accent = isDark ? Color.brand("6DBE85") : Color.brand("2F7A49")
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.brand("C9C3B3")).frame(width: 11, height: 11) }
            }
            Text("Friday").font(.system(size: 22, weight: .semibold))
            Text("Pesto night at Dana's, 7:00 pm.")
            Text("Bring: basil, pine nuts, a hard cheese.")
            HStack(spacing: 4) {
                Text("Recipe:")
                Rectangle().fill(accent).frame(width: 2, height: 20)
            }
        }
        .font(.system(size: 17))
        .foregroundStyle(ink)
        .padding(28)
        .frame(width: 760, height: 460, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDark ? Color.brand("2B2F2A") : Color.brand("FAF7EE"))
                .shadow(color: isDark ? .black.opacity(0.45) : Color.brand("2B2F2A").opacity(0.18), radius: 30, y: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isDark ? Color.brand("F6EFD9").opacity(0.08) : Color.brand("2B2F2A").opacity(0.10))
        )
        .position(x: size.width / 2, y: size.height - 222 - 230 + 38)
    }
}

private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.25, y: rect.minY - rect.height * 0.15),
            control2: CGPoint(x: rect.width * 0.75, y: rect.minY - rect.height * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.75, y: rect.maxY + rect.height * 0.15),
            control2: CGPoint(x: rect.width * 0.25, y: rect.maxY + rect.height * 0.15)
        )
        return path
    }
}

private extension Color {
    static func brand(_ hex: String) -> Color {
        Color(hex: hex) ?? .clear
    }
}
