// SPDX-License-Identifier: MIT
import CoreGraphics
import PestoCore

/// Card sizes, row counts and total keyboard height for the chosen `KeyboardSize` and device geometry.
enum KeyboardLayout {
    static func rows(size: KeyboardSize, isRegular: Bool, isLandscape: Bool) -> Int {
        if isRegular || isLandscape { return 1 }
        return size == .small ? 1 : 2
    }

    static func cardSize(size: KeyboardSize, isRegular: Bool) -> CGSize {
        if isRegular {
            let width: CGFloat = switch size {
            case .small: 180
            case .medium: 228
            case .large: 260
            }
            return CGSize(width: width, height: (width / CardGridLayout.aspectRatio).rounded())
        }
        return switch size {
        case .small: CGSize(width: 140, height: 78)
        case .medium: CGSize(width: 150, height: 88)
        case .large: CGSize(width: 180, height: 110)
        }
    }

    static func shelfHeight(size: KeyboardSize, isRegular: Bool, isLandscape: Bool) -> CGFloat {
        let count = rows(size: size, isRegular: isRegular, isLandscape: isLandscape)
        let card = cardSize(size: size, isRegular: isRegular)
        return CGFloat(count) * card.height + CGFloat(max(count - 1, 0)) * 6
    }

    static func totalHeight(size: KeyboardSize, isRegular: Bool, isLandscape: Bool, isSearching: Bool) -> CGFloat {
        let chrome: CGFloat = 94
        let base = chrome + shelfHeight(size: size, isRegular: isRegular, isLandscape: isLandscape)
        return isSearching ? KeyboardSearchMetrics.totalHeight(
            size: size,
            isRegular: isRegular,
            isLandscape: isLandscape
        ) : base
    }
}
