// SPDX-License-Identifier: MIT
import Foundation

public enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
