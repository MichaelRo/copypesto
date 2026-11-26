// SPDX-License-Identifier: MIT
import CoreGraphics
import PestoCore

/// The search page's sizes (ADR 0066): iOS's key metrics, and a results tray whose rows follow the keyboard's size.
/// The letter area has a fixed height, so a four-row script (Thai) gets shorter keys instead of a taller keyboard.
enum KeyboardSearchMetrics {
    static func resultRows(size: KeyboardSize, isRegular: Bool, isLandscape: Bool) -> Int {
        isRegular || isLandscape || size != .large ? 1 : 2
    }

    static func resultCard(size: KeyboardSize, isRegular: Bool) -> CGSize {
        if isRegular { return CGSize(width: 160, height: size == .small ? 80 : 92) }
        return switch size {
        case .small: CGSize(width: 140, height: 64)
        case .medium: CGSize(width: 150, height: 88)
        case .large: CGSize(width: 140, height: 78)
        }
    }

    static func fieldHeight(isRegular: Bool, isLandscape: Bool) -> CGFloat {
        isRegular ? 40 : isLandscape ? 32 : 36
    }

    static func rowGap(isRegular: Bool, isLandscape: Bool) -> CGFloat {
        isRegular ? 8 : isLandscape ? 6 : 11
    }

    static func keyGap(isRegular: Bool) -> CGFloat {
        isRegular ? 8 : 6
    }

    static func letterAreaHeight(isRegular: Bool, isLandscape: Bool) -> CGFloat {
        let key: CGFloat = isRegular ? 52 : isLandscape ? 34 : 42
        return key * 3 + rowGap(isRegular: isRegular, isLandscape: isLandscape) * 2
    }

    static func keyHeight(rowCount: Int, isRegular: Bool, isLandscape: Bool) -> CGFloat {
        let rows = CGFloat(max(rowCount, 1))
        let gaps = rowGap(isRegular: isRegular, isLandscape: isLandscape) * (rows - 1)
        return ((letterAreaHeight(isRegular: isRegular, isLandscape: isLandscape) - gaps) / rows).rounded(.down)
    }

    static func bottomKeyHeight(isRegular: Bool, isLandscape: Bool) -> CGFloat {
        isRegular ? 52 : isLandscape ? 34 : 42
    }

    static func trayHeight(size: KeyboardSize, isRegular: Bool, isLandscape: Bool) -> CGFloat {
        let rows = CGFloat(resultRows(size: size, isRegular: isRegular, isLandscape: isLandscape))
        let card = landscapeAdjusted(resultCard(size: size, isRegular: isRegular), isLandscape: isLandscape)
        return rows * card.height + (rows - 1) * 6 + 12
    }

    static func landscapeAdjusted(_ card: CGSize, isLandscape: Bool) -> CGSize {
        isLandscape ? CGSize(width: 140, height: 64) : card
    }

    static func sectionSpacing(isRegular: Bool, isLandscape: Bool) -> CGFloat {
        isRegular ? 9 : isLandscape ? 6 : 8
    }

    static func totalHeight(size: KeyboardSize, isRegular: Bool, isLandscape: Bool) -> CGFloat {
        let spacing = sectionSpacing(isRegular: isRegular, isLandscape: isLandscape)
        let edges: CGFloat = isRegular ? 18 : isLandscape ? 10 : 14
        return edges + fieldHeight(isRegular: isRegular, isLandscape: isLandscape)
            + trayHeight(size: size, isRegular: isRegular, isLandscape: isLandscape)
            + letterAreaHeight(isRegular: isRegular, isLandscape: isLandscape)
            + bottomKeyHeight(isRegular: isRegular, isLandscape: isLandscape)
            + spacing * 3
    }
}
