// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

extension Color {
    /// Status text ("Granted", "Not granted") in a green and a red that read as text on a light grouped row, which the
    /// system's own `.green` and `.red` do not (the accessibility audit measured them under 4.5:1).
    static let statusGood = status(
        light: NSColor(srgbRed: 0.07, green: 0.43, blue: 0.20, alpha: 1),
        dark: NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
    )
    static let statusBad = status(
        light: NSColor(srgbRed: 0.74, green: 0.07, blue: 0.11, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.42, blue: 0.42, alpha: 1)
    )

    static let statusWarning = status(
        light: NSColor(srgbRed: 0.54, green: 0.29, blue: 0.0, alpha: 1),
        dark: NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
    )

    /// A solid fill that white text reads on at 4.5:1 in both appearances. The two values are `DestructiveFill` in
    /// Core, where the contrast is tested (Shared cannot import Core); `StatusColorsTests` keeps them equal.
    static let statusBadFill = status(light: NSColor(hex: "BD121C"), dark: NSColor(hex: "C72A2A"))

    private static func status(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1
        )
    }
}
