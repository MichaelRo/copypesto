// SPDX-License-Identifier: MIT
import Foundation

/// How large the iOS keyboard's clip cards are (chosen in iOS Settings -> Clipboard, AutoFill & keyboard).
public enum KeyboardSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
}
