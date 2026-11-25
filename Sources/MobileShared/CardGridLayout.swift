// SPDX-License-Identifier: MIT
import CoreGraphics

enum CardGridLayout {
    static let minimumCardWidth: CGFloat = 190
    static let spacing: CGFloat = 12
    static let margin: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let aspectRatio: CGFloat = 10.0 / 9.0
    static let autoScrollEdgeZone: CGFloat = 72
    static let autoScrollMaxSpeed: CGFloat = 620

    static func columnCount(width: CGFloat, isAccessibilitySize: Bool) -> Int {
        guard !isAccessibilitySize else { return 1 }
        guard width.isFinite, width > 0 else { return 2 }
        return max(2, Int((width + spacing) / (minimumCardWidth + spacing)))
    }

    static func cardWidth(rowWidth: CGFloat, columns: Int) -> CGFloat {
        let count = CGFloat(max(columns, 1))
        return max(0, (rowWidth - spacing * (count - 1)) / count)
    }

    static func cardHeight(forWidth width: CGFloat) -> CGFloat {
        width / aspectRatio
    }

    static func lineLimit(height: CGFloat, lineHeight: CGFloat) -> Int {
        guard lineHeight > 0, height.isFinite else { return 1 }
        return max(1, Int(height / lineHeight))
    }

    /// Maps a point inside the padded `LazyVGrid` coordinate space to its card index in `O(1)` time.
    static func cardIndex(
        at point: CGPoint,
        itemCount: Int,
        columns: Int,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        allowsGutter: Bool = false
    )
    -> Int? {
        guard itemCount > 0, columns >= 1, cardWidth > 0, cardHeight > 0,
              point.x.isFinite, point.y.isFinite, point.y >= 0 else { return nil }
        let count = CGFloat(columns)
        let totalWidth = count * cardWidth + max(0, count - 1) * spacing
        let resolvedX: CGFloat
        if allowsGutter {
            guard point.x >= -margin, point.x <= totalWidth + margin else { return nil }
            resolvedX = min(max(point.x, 0), totalWidth)
        } else {
            guard point.x >= 0, point.x <= totalWidth else { return nil }
            resolvedX = point.x
        }
        let stepX = cardWidth + spacing
        let stepY = cardHeight + spacing
        let column = min(columns - 1, max(0, Int(resolvedX / stepX)))
        let row = max(0, Int(point.y / stepY))
        if !allowsGutter {
            let xInCell = resolvedX - CGFloat(column) * stepX
            let yInCell = point.y - CGFloat(row) * stepY
            guard xInCell <= cardWidth, yInCell <= cardHeight else { return nil }
        }
        let index = row * columns + column
        return index < itemCount ? index : nil
    }

    /// Points-per-second vertical auto-scroll velocity while dragging near the top or bottom viewport edge.
    static func edgeAutoScrollVelocity(
        touchY: CGFloat,
        visibleMinY: CGFloat,
        visibleMaxY: CGFloat,
        edgeZone: CGFloat = autoScrollEdgeZone,
        maxSpeed: CGFloat = autoScrollMaxSpeed
    )
    -> CGFloat {
        guard touchY.isFinite, visibleMinY.isFinite, visibleMaxY.isFinite,
              edgeZone.isFinite, maxSpeed.isFinite,
              visibleMaxY > visibleMinY, edgeZone > 0, maxSpeed > 0 else { return 0 }
        let effectiveZone = min(edgeZone, (visibleMaxY - visibleMinY) / 3)
        guard effectiveZone > 0 else { return 0 }
        if touchY > visibleMaxY - effectiveZone {
            let fraction = min(1, max(0, (touchY - (visibleMaxY - effectiveZone)) / effectiveZone))
            return fraction * fraction * maxSpeed
        }
        if touchY < visibleMinY + effectiveZone {
            let fraction = min(1, max(0, (visibleMinY + effectiveZone - touchY) / effectiveZone))
            return -(fraction * fraction) * maxSpeed
        }
        return 0
    }
}
