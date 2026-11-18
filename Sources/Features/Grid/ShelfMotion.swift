// SPDX-License-Identifier: MIT
import CoreGraphics
import SwiftUI

enum ShelfMotion {
    /// A collection switch is one quick change of state, so it takes the family's.
    static let switchEase = Animation.pestoQuick
    static let collectionSlide: CGFloat = 18
    /// ⌘[ and ⌘] presses closer together than this become one switch (`cyclePinboard`).
    static let cycleCoalesce = Duration.milliseconds(80)

    /// A list change is animated only when it is one the eye can follow (`ListChangeMotion`).
    static func shouldAnimateChange(from old: [UUID], to new: [UUID]) -> Bool {
        ListChangeMotion.shouldAnimateChange(from: old, to: new)
    }

    /// +1 when the shelf moves to a collection further along the chips, -1 when it moves back.
    static func switchDirection(order: [UUID?], from old: UUID?, to new: UUID?) -> CGFloat {
        guard let oldIndex = order.firstIndex(of: old), let newIndex = order.firstIndex(of: new) else { return 1 }
        return newIndex >= oldIndex ? 1 : -1
    }
}
