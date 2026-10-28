// SPDX-License-Identifier: MIT
import CoreGraphics

/// When a row of icon-only chips shows a chip's name. One state for the whole row, not one per chip: resting on a chip
/// opens its name after a short dwell, moving to a neighbor while a name is open switches at once, and leaving the row
/// closes it after a short grace, so a pass across the row opens nothing and a jittery edge does not flicker.
public struct ChipHoverIntent: Equatable, Sendable {
    public static let dwell = 0.16
    public static let grace = 0.12
    public static let warmWindow = 0.45

    public private(set) var expanded: Int?
    private var candidate: Int?
    private var candidateSince = 0.0
    private var leftAt: Double?
    private var closedAt: Double?

    public init() {}

    public var isPending: Bool {
        candidate != nil || leftAt != nil
    }

    public mutating func pointerMoved(over index: Int?, at now: Double) {
        guard let index else {
            candidate = nil
            if expanded != nil, leftAt == nil { leftAt = now }
            return
        }
        leftAt = nil
        if index == expanded {
            candidate = nil
            return
        }
        if expanded != nil {
            expanded = index
            candidate = nil
            return
        }
        if let closedAt, now - closedAt < Self.warmWindow {
            expanded = index
            candidate = nil
            return
        }
        if candidate != index {
            candidate = index
            candidateSince = now
        }
    }

    public mutating func tick(at now: Double) {
        if let candidate, now - candidateSince >= Self.dwell {
            expanded = candidate
            self.candidate = nil
        }
        if let leftAt, now - leftAt >= Self.grace {
            expanded = nil
            closedAt = now
            self.leftAt = nil
        }
    }
}

/// Which chip the pointer is on, worked out from the chips' resting slots and not from where they are now. A chip that
/// opens its name grows and pushes the others along; matching the pointer to the moved chips would let it land on the
/// chip after the next. The resting slots do not move, so the answer does not depend on the animation.
public enum ChipSlots {
    public struct Expanded: Equatable, Sendable {
        public var index: Int
        public var width: CGFloat

        public init(index: Int, width: CGFloat) {
            self.index = index
            self.width = width
        }
    }

    public static func target(x: CGFloat, restWidths: [CGFloat], spacing: CGFloat, expanded: Expanded?) -> Int? {
        guard !restWidths.isEmpty, x >= 0 else { return nil }
        var start: CGFloat = 0
        for (index, width) in restWidths.enumerated() {
            let isLast = index == restWidths.count - 1
            let end = isLast ? start + width : start + width + spacing / 2
            if x < end { return index }
            start += width + spacing
        }
        if let expanded, expanded.index == restWidths.count - 1 {
            let lastStart = restWidths.dropLast().reduce(CGFloat(0)) { $0 + $1 + spacing }
            if x < lastStart + expanded.width { return expanded.index }
        }
        return nil
    }
}
