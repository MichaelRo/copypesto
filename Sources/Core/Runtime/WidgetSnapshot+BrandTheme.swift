// SPDX-License-Identifier: MIT
import Foundation

public extension WidgetSnapshot.Theme {
    /// Basil's, for a widget with no snapshot to read.
    static let brand = WidgetSnapshot.Theme(
        lightGround: AppTheme.basil.groundHex(dark: false), darkGround: AppTheme.basil.groundHex(dark: true),
        lightAccent: AppTheme.basil.accentHex(dark: false), darkAccent: AppTheme.basil.accentHex(dark: true)
    )
}
