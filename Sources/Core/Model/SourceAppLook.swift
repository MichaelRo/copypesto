// SPDX-License-Identifier: MIT
import Foundation

/// The app a clip came from and its color, as the keyboard, AutoFill and the widgets carry them to draw a card's icon
/// and foot glow (ADRs 0068, 0074). A color is kept only as `#RRGGBB` and never as the placeholder grey.
public struct SourceAppLook: Equatable, Sendable {
    public static let placeholderColor = "#888888"

    public let bundleID: String?
    public let colorHex: String?

    public init(bundleID: String?, colorHex: String?) {
        let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.bundleID = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxBundleIDCharacters))
        self.colorHex = Self.color(colorHex)
    }

    public static let none = SourceAppLook(bundleID: nil, colorHex: nil)

    static let maxBundleIDCharacters = 160

    static func color(_ hex: String?) -> String? {
        guard let hex, hex.count == 7, hex.first == "#",
              hex.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        let upper = hex.uppercased()
        return upper == placeholderColor ? nil : upper
    }
}
