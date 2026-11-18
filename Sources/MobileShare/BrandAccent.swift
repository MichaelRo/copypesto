// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The brand green for an extension, which cannot read the person's theme (ADR 0047): the share extension and the
/// AutoFill extension both draw with it.
enum BrandAccent {
    static let color = Color(uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? BrandPalette.accentDark : BrandPalette.accentLight
        let value = UInt32(hex, radix: 16) ?? 0
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1
        )
    })
}
