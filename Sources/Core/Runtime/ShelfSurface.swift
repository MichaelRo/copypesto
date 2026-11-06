// SPDX-License-Identifier: MIT
import Foundation

/// What the shelf is drawn on: Liquid Glass that shows a little of the desktop, or a plain ground that is the same on
/// every desktop (ADR 0035). Reduce Transparency always gives the plain ground.
public enum ShelfSurface: String, CaseIterable, Sendable {
    case glass
    case solid

    /// How much of the focused card's colour wash a solid ground keeps. Over glass the wash is full strength.
    public static let softWashShare = 0.35

    private static let fullWash: [Double] = [0.22, 0.12, 0.18]

    public init(stored: String) {
        self = Self(rawValue: stored) ?? .solid
    }

    public var title: String {
        switch self {
        case .glass: "Glass"
        case .solid: "Solid"
        }
    }

    public static func drawsGlass(stored: String, reduceTransparency: Bool) -> Bool {
        !reduceTransparency && ShelfSurface(stored: stored) == .glass
    }

    /// The opacities of the wash's three corners (top left, bottom left, bottom right).
    public static func washOpacities(solid: Bool) -> [Double] {
        solid ? fullWash.map { $0 * softWashShare } : fullWash
    }
}
