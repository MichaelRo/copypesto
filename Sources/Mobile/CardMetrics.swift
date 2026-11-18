// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import Synchronization
import UIKit

/// Sizes on one card: Core's fixed steps scaled with the card's width (`CardTextScale`; `scaledFont` adds Dynamic
/// Type, capped at `maxTextScale`), and the whole lines of text that fit above the line of facts.
struct CardMetrics {
    static let inset: CGFloat = 12
    static let footGap: CGFloat = 6

    let width: CGFloat
    private let category: UIContentSizeCategory

    init(width: CGFloat, typeSize: DynamicTypeSize) {
        self.width = width
        category = UIContentSizeCategory(typeSize)
    }

    var height: CGFloat {
        CardGridLayout.cardHeight(forWidth: width)
    }

    static let maxTextScale: CGFloat = 1.6

    func points(_ base: Double) -> CGFloat {
        CardTextScale.size(CGFloat(base), cardWidth: width)
    }

    func lineHeight(_ style: UIFont.TextStyle) -> CGFloat {
        LineHeights.height(of: style, in: category)
    }

    var bodyHeight: CGFloat {
        height - Self.inset * 2 - Self.footGap - lineHeight(.caption1)
    }

    func lines(_ style: UIFont.TextStyle) -> Int {
        CardGridLayout.lineLimit(height: bodyHeight, lineHeight: lineHeight(style))
    }
}

/// The line height of a text style at a content size category, looked up once: every card on screen asks, on every
/// draw, and the answer changes only with the person's text size.
enum LineHeights {
    private struct Key: Hashable {
        let style: UIFont.TextStyle
        let category: UIContentSizeCategory
    }

    private static let cache = Mutex<[Key: CGFloat]>([:])

    static var cachedCount: Int {
        cache.withLock { $0.count }
    }

    static func height(of style: UIFont.TextStyle, in category: UIContentSizeCategory) -> CGFloat {
        let key = Key(style: style, category: category)
        if let known = cache.withLock({ $0[key] }) { return known }
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let height = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).lineHeight
        cache.withLock { $0[key] = height }
        return height
    }
}
