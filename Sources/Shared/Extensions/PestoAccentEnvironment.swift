// SPDX-License-Identifier: MIT
import SwiftUI

extension EnvironmentValues {
    /// The user's chosen accent (Pesto green by default). `Color.accentColor` ignores `.tint`, so custom-drawn chrome
    /// (focus rings, chips, selections) reads this instead. Each window's root view sets it.
    @Entry var pestoAccent: Color = .accentColor
    /// The text on a button filled with `pestoAccent` (`PestoProminentButtonStyle`).
    @Entry var pestoAccentLabel: Color = .white
}
