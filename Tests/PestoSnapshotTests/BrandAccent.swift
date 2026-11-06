// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
@testable import Pesto

extension View {
    /// What every Pesto window root does (`pestoAccented`): without it a snapshot draws the system's blue, so a
    /// baseline could not show the brand green or catch a view that forgot to read the accent.
    func inBrandAccent() -> some View {
        pestoAccented(stored: AccentChoice.defaultStored, theme: AppTheme.basil.rawValue, darkTheme: "")
    }
}
