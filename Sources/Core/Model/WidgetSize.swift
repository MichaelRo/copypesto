// SPDX-License-Identifier: MIT
import Foundation

/// The widget's families on iPhone and iPad (ADRs 0052, 0067), named here so Core decides each one's grid of card
/// tiles. Each grid keeps a tile near the card's 10:9 shape inside the family's content area: one tile fills a small
/// widget, two sit side by side in a medium one, two by two in a large one, two by four in an extra large one (iPad).
public enum WidgetSize: CaseIterable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    public struct Grid: Equatable, Sendable {
        public let rows: Int
        public let columns: Int

        public init(rows: Int, columns: Int) {
            self.rows = rows
            self.columns = columns
        }
    }

    /// At an accessibility text size a tile needs more room, so fewer fit.
    public func grid(accessibilityText: Bool) -> Grid {
        switch self {
        case .small: Grid(rows: 1, columns: 1)
        case .medium: Grid(rows: 1, columns: accessibilityText ? 1 : 2)
        case .large: Grid(rows: 2, columns: accessibilityText ? 1 : 2)
        case .extraLarge: Grid(rows: 2, columns: accessibilityText ? 2 : 4)
        }
    }

    public func clipCount(accessibilityText: Bool) -> Int {
        let grid = grid(accessibilityText: accessibilityText)
        return grid.rows * grid.columns
    }

    public func columns(accessibilityText: Bool) -> Int {
        grid(accessibilityText: accessibilityText).columns
    }

    /// Medium and large page through the list (ADR 0067); a small widget is one card and an extra large one has room
    /// for all it shows.
    public var pages: Bool {
        self == .medium || self == .large
    }

    public func pageCount(of count: Int, accessibilityText: Bool) -> Int {
        guard pages, count > 0 else { return 1 }
        let perPage = clipCount(accessibilityText: accessibilityText)
        return (count + perPage - 1) / perPage
    }
}
