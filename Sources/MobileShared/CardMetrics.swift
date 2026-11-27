// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import Synchronization
import UIKit

/// Sizes on one card: Core's fixed steps scaled with the card's width (`CardTextScale`; `scaledFont` adds Dynamic
/// Type, capped at `maxTextScale`), and the whole lines of text that fit above the line of facts.
struct CardMetrics {
    static let inset: CGFloat = 12
    static let compactInset: CGFloat = 10
    static let footGap: CGFloat = 6
    static let titleGap: CGFloat = 4

    let width: CGFloat
    private let fixedHeight: CGFloat?
    private let category: UIContentSizeCategory

    init(width: CGFloat, height: CGFloat? = nil, typeSize: DynamicTypeSize) {
        self.width = width
        fixedHeight = height
        category = UIContentSizeCategory(typeSize)
    }

    var height: CGFloat {
        fixedHeight ?? CardGridLayout.cardHeight(forWidth: width)
    }

    /// Compact keyboard cards keep slightly tighter inner margins so large cards earn an extra readable text line.
    var cardInset: CGFloat {
        guard let fixedHeight, fixedHeight < 140 else { return Self.inset }
        return Self.compactInset
    }

    static let maxTextScale: CGFloat = 1.6

    func points(_ base: Double) -> CGFloat {
        CardTextScale.size(CGFloat(base), cardWidth: width)
    }

    func lineHeight(_ style: UIFont.TextStyle) -> CGFloat {
        LineHeights.height(of: style, in: category)
    }

    var bodyHeight: CGFloat {
        bodyHeight(hasTitle: false)
    }

    func bodyHeight(hasTitle: Bool = false) -> CGFloat {
        let titleReserve = hasTitle ? lineHeight(.footnote) + Self.titleGap : 0
        let verticalPadding = cardInset * 2
        let gap = fixedHeight.map { $0 < 140 ? CGFloat(4) : Self.footGap } ?? Self.footGap
        return max(0, height - verticalPadding - gap - lineHeight(.caption1) - titleReserve)
    }

    func lines(_ style: UIFont.TextStyle, hasTitle: Bool = false) -> Int {
        CardGridLayout.lineLimit(height: bodyHeight(hasTitle: hasTitle), lineHeight: lineHeight(style))
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
