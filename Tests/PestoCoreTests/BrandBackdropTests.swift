// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("The brand backdrop")
struct BrandBackdropTests {
    private func grounds(dark: Bool) -> [String] {
        let stops = BrandBackdrop.stops(dark: dark)
        let glowOnEachStop = stops.map {
            ContrastRatio.blend(BrandBackdrop.basilGlow.hex, over: $0, alpha: BrandBackdrop.basilGlow.opacity)
        }
        let goldOnEachStop = stops.map {
            ContrastRatio.blend(BrandBackdrop.goldGlow.hex, over: $0, alpha: BrandBackdrop.goldGlow.opacity)
        }
        return stops + glowOnEachStop + goldOnEachStop
    }

    @Test("primary text reads on every part of the light backdrop, with and without a glow on it")
    func whenLight_thenTextIsReadable() {
        for ground in grounds(dark: false) {
            #expect(ContrastRatio.between(BrandPalette.mortar, ground) >= 7, "ground \(ground)")
        }
    }

    @Test("primary text reads on every part of the dark backdrop, with and without a glow on it")
    func whenDark_thenTextIsReadable() {
        for ground in grounds(dark: true) {
            #expect(ContrastRatio.between(BrandPalette.parmesan, ground) >= 7, "ground \(ground)")
        }
    }

    @Test("the accent reads as text on the backdrop's plain stops")
    func whenAccent_thenReadableOnStops() {
        for stop in BrandBackdrop.stops(dark: false) {
            #expect(ContrastRatio.between(BrandPalette.accentLight, stop) >= 4.5, "light stop \(stop)")
        }
        for stop in BrandBackdrop.stops(dark: true) {
            #expect(ContrastRatio.between(BrandPalette.accentDark, stop) >= 4.5, "dark stop \(stop)")
        }
    }
}
