// SPDX-License-Identifier: MIT
import CoreGraphics

/// Which edge of the screen the shelf hangs from: the bottom, resting on the Dock, or the top, just under the menu bar
/// and the notch.
public enum ShelfPosition: String, CaseIterable, Sendable {
    case bottom
    /// The top shelf. The name is the first one it had and is what earlier builds and backups stored, so it stays; the
    /// person reads "Top". It hangs from the bottom of the menu bar, below the notch on a Mac that has one, so on every
    /// screen it is the top edge.
    case underNotch

    /// The numbers of a display the placement needs, as plain values.
    public struct Screen: Equatable, Sendable {
        public let frame: CGRect
        public let visibleFrame: CGRect
        /// The height of the notch's safe area (0 on a screen without one).
        public let safeAreaTop: CGFloat

        public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat) {
            self.frame = frame
            self.visibleFrame = visibleFrame
            self.safeAreaTop = safeAreaTop
        }
    }

    public init(stored: String) {
        self = Self(rawValue: stored) ?? .bottom
    }

    public var title: String {
        switch self {
        case .bottom: "Bottom"
        case .underNotch: "Top"
        }
    }

    public func frame(on screen: Screen, height: CGFloat) -> CGRect {
        let visible = screen.visibleFrame
        let shown = min(height, visible.height)
        switch self {
        case .bottom:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: shown)
        case .underNotch:
            let top = min(visible.maxY, screen.frame.maxY - screen.safeAreaTop)
            return CGRect(x: visible.minX, y: max(visible.minY, top - shown), width: visible.width, height: shown)
        }
    }

    /// The layer's starting offset when the shelf slides in (and its ending offset when it leaves).
    public func slideOffset(height: CGFloat) -> CGFloat {
        self == .bottom ? -height : height
    }

    public var hoverCardOpensAbove: Bool {
        self == .bottom
    }

    /// The shelf's hover card opens away from the shelf. A card over any other window (the floating window) opens
    /// above.
    public static func hoverCardOpensAbove(hostIsShelf: Bool, position: ShelfPosition) -> Bool {
        !hostIsShelf || position.hoverCardOpensAbove
    }
}
