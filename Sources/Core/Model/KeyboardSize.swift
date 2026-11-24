// SPDX-License-Identifier: MIT
import Foundation

/// How large the iOS keyboard's clip cards are (chosen in iOS Settings -> Clipboard, AutoFill & keyboard, or inside the
/// keyboard itself).
public enum KeyboardSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var next: KeyboardSize {
        switch self {
        case .small: .medium
        case .medium: .large
        case .large: .small
        }
    }

    public var shortLabel: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }

    public var displayName: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}
