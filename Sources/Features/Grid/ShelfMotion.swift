// SPDX-License-Identifier: MIT
import CoreGraphics
import SwiftUI

enum ShelfMotion {
    static let glide = 0.2
    static let change = 0.22
    static let switchEase = Animation.easeOut(duration: 0.18)
    static let collectionSlide: CGFloat = 18

    /// A list change is animated only when it is one the eye can follow: one clip added or removed, a swap of one for
    /// another, or one clip brought to the front. A search, filter or sort rewrites the whole list and must not
    /// animate.
    static func shouldAnimateChange(from old: [UUID], to new: [UUID]) -> Bool {
        guard old != new else { return false }
        let before = Set(old)
        let after = Set(new)
        let changed = before.symmetricDifference(after).count
        if changed > 0 { return changed <= 2 }
        guard let first = new.first, old.contains(first) else { return false }
        return Array(new.dropFirst()) == old.filter { $0 != first }
    }

    /// +1 when the shelf moves to a collection further along the chips, -1 when it moves back.
    static func switchDirection(order: [UUID?], from old: UUID?, to new: UUID?) -> CGFloat {
        guard let oldIndex = order.firstIndex(of: old), let newIndex = order.firstIndex(of: new) else { return 1 }
        return newIndex >= oldIndex ? 1 : -1
    }
}
