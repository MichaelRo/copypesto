// SPDX-License-Identifier: MIT
import SwiftUI
import Testing
@testable import Pesto

@Suite("Adaptive contrast")
struct AdaptiveContrastTests {
    @Test("quiet text is 70% of the primary color, and 90% under Increase Contrast")
    func whenContrastChanges_thenQuietTextFollows() {
        #expect(AdaptiveContrast.quietOpacity(for: .standard) == 0.7)
        #expect(AdaptiveContrast.quietOpacity(for: .increased) == 0.9)
    }

    @Test("an inactive chip gets an outline under Increase Contrast or Differentiate Without Color, and not otherwise")
    func whenDifferentiating_thenInactiveChipsAreOutlined() {
        #expect(AdaptiveContrast.inactiveOutlineOpacity(contrast: .standard, differentiateWithoutColor: false) == 0)
        #expect(AdaptiveContrast.inactiveOutlineOpacity(contrast: .increased, differentiateWithoutColor: false) > 0)
        #expect(AdaptiveContrast.inactiveOutlineOpacity(contrast: .standard, differentiateWithoutColor: true) > 0)
    }
}
