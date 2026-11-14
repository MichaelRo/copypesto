// SPDX-License-Identifier: MIT
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

extension Color {
    /// Status text ("Granted", "Not granted") in a green and a red that read as text on a light grouped row, which the
    /// system's own `.green` and `.red` do not (the accessibility audit measured them under 4.5:1).
    static let statusGood = status(
        light: PlatformColor(srgbRed: 0.07, green: 0.43, blue: 0.20),
        dark: PlatformColor(srgbRed: 0.20, green: 0.78, blue: 0.35)
    )
    static let statusBad = status(
        light: PlatformColor(srgbRed: 0.74, green: 0.07, blue: 0.11),
        dark: PlatformColor(srgbRed: 1.0, green: 0.42, blue: 0.42)
    )

    static let statusWarning = status(
        light: PlatformColor(srgbRed: 0.54, green: 0.29, blue: 0.0),
        dark: PlatformColor(srgbRed: 1.0, green: 0.62, blue: 0.04)
    )

    /// A solid fill that white text reads on at 4.5:1 in both appearances. The two values are `DestructiveFill` in
    /// Core, where the contrast is tested (Shared cannot import Core); `StatusColorsTests` keeps them equal.
    static let statusBadFill = status(light: PlatformColor(hex: "BD121C"), dark: PlatformColor(hex: "C72A2A"))

    private static func status(light: PlatformColor, dark: PlatformColor) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
        #else
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
        #endif
    }
}

#if os(macOS)
private typealias PlatformColor = NSColor
#else
private typealias PlatformColor = UIColor
#endif

private extension PlatformColor {
    convenience init(srgbRed red: Double, green: Double, blue: Double) {
        #if os(macOS)
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        self.init(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }

    convenience init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(
            srgbRed: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
