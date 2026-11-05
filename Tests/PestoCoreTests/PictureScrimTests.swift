// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Picture scrim")
struct PictureScrimTests {
    @Test("the app name and the age read at 4.5 to 1 or better over a white picture")
    func whenWhitePicture_thenHeaderTextPassesAA() {
        #expect(PictureScrim.worstCaseContrast(textOpacity: PictureScrim.nameOpacity) >= 4.5)
        #expect(PictureScrim.worstCaseContrast(textOpacity: PictureScrim.ageOpacity) >= 4.5)
    }

    @Test("the shortcut pill's text reads at 4.5 to 1 or better over a white picture")
    func whenWhitePicture_thenPillPassesAA() {
        #expect(PictureScrim.worstCaseContrast(coverOpacity: PictureScrim.pillOpacity, textOpacity: 1) >= 4.5)
    }

    @Test("a weaker scrim would fail, so the numbers are what keep the guarantee")
    func whenScrimTooWeak_thenContrastFails() {
        #expect(PictureScrim.worstCaseContrast(coverOpacity: 0.4, textOpacity: 1) < 4.5)
    }

    @Test("the scrim is solid across the whole header band and fades below it")
    func whenOpacityAtHeight_thenSolidThenFading() {
        #expect(PictureScrim.opacity(atHeight: 0) == PictureScrim.topOpacity)
        #expect(PictureScrim.opacity(atHeight: Double(CardLayout.headerHeight)) == PictureScrim.topOpacity)
        #expect(PictureScrim.opacity(atHeight: Double(CardLayout.headerHeight) + PictureScrim.fadeHeight) == 0)
        let middle = PictureScrim.opacity(atHeight: Double(CardLayout.headerHeight) + PictureScrim.fadeHeight / 2)
        #expect(middle > 0 && middle < PictureScrim.topOpacity)
    }
}

@Suite("Picture fit")
struct PictureFitTests {
    @Test("ordinary pictures fill the card", arguments: [0.6, 0.75, 1.0, 1.33, 1.78, 2.0])
    func whenOrdinaryAspect_thenFill(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect) == .fill)
    }

    @Test("very tall and very wide pictures are fitted instead of cropped to a band", arguments: [
        0.59, 0.3, 0.1, 2.01, 3.0, 10.0
    ])
    func whenExtremeAspect_thenFit(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect) == .fit)
    }

    @Test("an aspect that cannot be trusted is fitted", arguments: [0.0, -1.0, Double.nan, Double.infinity])
    func whenUnusableAspect_thenFit(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect) == .fit)
    }
}
