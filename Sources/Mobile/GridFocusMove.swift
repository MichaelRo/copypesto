// SPDX-License-Identifier: MIT
import SwiftUI

/// Where an arrow key moves the focused card in a grid of `columns` columns read in reading order. Nil at an edge, so
/// the key falls through (the scroll view or the system may still use it). Left and right follow the layout direction.
enum GridFocusMove {
    enum Direction: Equatable { case up, down, back, forward }

    static func direction(of key: KeyEquivalent, layout: LayoutDirection) -> Direction? {
        switch key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: layout == .rightToLeft ? .forward : .back
        case .rightArrow: layout == .rightToLeft ? .back : .forward
        default: nil
        }
    }

    static func target(from index: Int, count: Int, columns: Int, moving direction: Direction) -> Int? {
        guard count > 0, columns > 0, (0..<count).contains(index) else { return nil }
        let next = switch direction {
        case .up: index - columns
        case .down: index + columns
        case .back: index % columns == 0 ? -1 : index - 1
        case .forward: (index + 1) % columns == 0 ? count : index + 1
        }
        return (0..<count).contains(next) ? next : nil
    }
}
