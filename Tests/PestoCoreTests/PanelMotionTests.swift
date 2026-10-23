// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("PanelMotion")
struct PanelMotionTests {
    @Test("panels slide by default")
    func whenMotionAllowed_thenSlides() {
        #expect(PanelMotion.slides(reduceMotion: false))
    }

    @Test("with Reduce Motion on, panels only fade")
    func whenReduceMotion_thenNoSlide() {
        #expect(!PanelMotion.slides(reduceMotion: true))
    }

    @Test("the shelf closes faster than the 0.25 s it opens in, because a paste waits for it")
    func hideIsQuickerThanShow() {
        #expect(PanelMotion.hideDuration <= 0.15)
        #expect(PanelMotion.hideDuration < 0.25)
    }
}
