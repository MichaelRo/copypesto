// SPDX-License-Identifier: MIT
import CoreGraphics

enum CardGridLayout {
    static let minimumCardWidth: CGFloat = 190
    static let spacing: CGFloat = 12
    static let margin: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let aspectRatio: CGFloat = 10.0 / 9.0

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
}
