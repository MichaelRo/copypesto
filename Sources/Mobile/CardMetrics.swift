// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// Sizes on one card: Core's fixed steps scaled with the card's width (`CardTextScale`; `scaledFont` adds Dynamic
/// Type, capped at `maxTextScale`), and the whole lines of text that fit above the line of facts.
struct CardMetrics {
    static let inset: CGFloat = 12
    static let footGap: CGFloat = 6

    let width: CGFloat
    private let traits: UITraitCollection

    init(width: CGFloat, typeSize: DynamicTypeSize) {
        self.width = width
        traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
    }

    var height: CGFloat {
        CardGridLayout.cardHeight(forWidth: width)
    }

    static let maxTextScale: CGFloat = 1.6

    func points(_ base: Double) -> CGFloat {
        CardTextScale.size(CGFloat(base), cardWidth: width)
    }

    func lineHeight(_ style: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).lineHeight
    }

    var bodyHeight: CGFloat {
        height - Self.inset * 2 - Self.footGap - lineHeight(.caption1)
    }

    func lines(_ style: UIFont.TextStyle) -> Int {
        CardGridLayout.lineLimit(height: bodyHeight, lineHeight: lineHeight(style))
    }
}
