// SPDX-License-Identifier: MIT
import Foundation

/// The widget's families on iPhone and iPad (ADR 0052), named here so Core decides how many card tiles each shows and
/// in how many columns.
public enum WidgetSize: CaseIterable, Sendable {
    case small
    case medium
    case large

    /// At an accessibility text size a tile needs more room, so fewer fit.
    public func clipCount(accessibilityText: Bool) -> Int {
        switch self {
        case .small: 1
        case .medium: accessibilityText ? 2 : 3
        case .large: accessibilityText ? 4 : 6
        }
    }

    public func columns(accessibilityText: Bool) -> Int {
        switch self {
        case .small: 1
        case .medium: clipCount(accessibilityText: accessibilityText)
        case .large: 2
        }
    }
}
