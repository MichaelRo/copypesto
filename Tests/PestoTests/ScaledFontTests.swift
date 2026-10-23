// SPDX-License-Identifier: MIT
import Testing
@testable import Pesto

@Suite("Scaled font")
struct ScaledFontTests {
    @Test("with no cap, the scaled size passes through unchanged")
    func whenUncapped_thenScaledSizePassesThrough() {
        #expect(ScaledFont.resolvedSize(scaled: 22, base: 11, maxScale: nil) == 22)
    }

    @Test("scaling within the cap passes through unchanged")
    func whenWithinCap_thenScaledSizePassesThrough() {
        #expect(ScaledFont.resolvedSize(scaled: 13, base: 11, maxScale: 1.4) == 13)
    }

    @Test("scaling past the cap is clamped to base * maxScale")
    @MainActor
    func whenPastCap_thenClamped() {
        let clamped = ScaledFont.resolvedSize(scaled: 30, base: 11, maxScale: 1.4)
        #expect(abs(clamped - 15.4) < 0.001)
    }

    @Test("scaling below the base size (Dynamic Type set smaller than default) is never clamped up")
    func whenBelowBase_thenPassesThrough() {
        #expect(ScaledFont.resolvedSize(scaled: 9, base: 11, maxScale: 1.4) == 9)
    }
}
