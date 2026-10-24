// SPDX-License-Identifier: MIT
import Foundation

public enum CollectionReorder {
    public enum Side: Equatable, Sendable {
        case before
        case after

        /// The half of a chip the pointer is over decides which edge the dragged chip lands on.
        public static func at(x: CGFloat, width: CGFloat) -> Side {
            x < width / 2 ? .before : .after
        }
    }

    /// The order after `moving` is dropped on the `side` of `target`. Dropping a chip next to itself changes nothing.
    public static func order(_ ids: [UUID], moving: UUID, relativeTo target: UUID, side: Side) -> [UUID] {
        guard moving != target, ids.contains(moving), ids.contains(target) else { return ids }
        var result = ids.filter { $0 != moving }
        guard let index = result.firstIndex(of: target) else { return ids }
        result.insert(moving, at: side == .before ? index : index + 1)
        return result
    }

    /// Where the dragged chip sits among the others (0 to `slotMidXs.count`) for a pointer at `pointerX`. `slotMidXs`
    /// are the
    /// other chips' centres as they were when the drag began, so the answer never follows the chips that are sliding. A
    /// chip changes sides only once the pointer is `deadband` past its centre, so a pointer resting on a boundary does
    /// not
    /// make the row flicker.
    public static func insertionIndex(
        slotMidXs: [CGFloat], pointerX: CGFloat, currentIndex: Int, deadband: CGFloat = 8
    )
    -> Int {
        slotMidXs.enumerated().reduce(0) { count, slot in
            let isBefore = slot.offset < currentIndex
            let threshold = isBefore ? slot.element - deadband : slot.element + deadband
            return pointerX > threshold ? count + 1 : count
        }
    }

    /// `ids` with `moving` taken out and put back at `index` among the rest.
    public static func order(_ ids: [UUID], moving: UUID, toIndex index: Int) -> [UUID] {
        guard ids.contains(moving) else { return ids }
        var result = ids.filter { $0 != moving }
        result.insert(moving, at: min(max(index, 0), result.count))
        return result
    }

    public struct InsertionBar: Equatable, Sendable {
        public let target: UUID
        public let side: Side

        public init(target: UUID, side: Side) {
            self.target = target
            self.side = side
        }
    }

    /// Where the insertion bar appears in the stationary `ids` row when `moving` would land at `index`, or nil when
    /// dropping at `index` leaves the order unchanged.
    public static func insertionBar(_ ids: [UUID], moving: UUID, toIndex index: Int) -> InsertionBar? {
        guard !ids.isEmpty, let sourceIndex = ids.firstIndex(of: moving) else { return nil }
        let clamped = min(max(index, 0), ids.count - 1)
        guard clamped != sourceIndex else { return nil }
        return InsertionBar(target: ids[clamped], side: clamped < sourceIndex ? .before : .after)
    }
}
