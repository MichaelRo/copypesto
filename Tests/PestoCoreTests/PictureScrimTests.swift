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

    @Test("every theme surface scrim keeps header text at 4.5 to 1 or better in light and dark")
    func whenAnyThemeSurfaceScrim_thenHeaderTextPassesAAInLightAndDark() {
        for theme in AppTheme.allCases {
            let darkGround = theme.groundHex(dark: true)
            #expect(PictureScrim.worstCaseContrast(
                coverHex: darkGround,
                textHex: BrandPalette.parmesan,
                textOpacity: PictureScrim.nameOpacity,
                pictureIsBright: true
            ) >= 4.5)
            #expect(PictureScrim.worstCaseContrast(
                coverHex: darkGround,
                textHex: BrandPalette.parmesan,
                textOpacity: PictureScrim.ageOpacity,
                pictureIsBright: true
            ) >= 4.5)

            let lightGround = theme.groundHex(dark: false)
            #expect(PictureScrim.worstCaseContrast(
                coverHex: lightGround,
                textHex: BrandPalette.mortar,
                textOpacity: PictureScrim.nameOpacity,
                pictureIsBright: false
            ) >= 4.5)
            #expect(PictureScrim.worstCaseContrast(
                coverHex: lightGround,
                textHex: BrandPalette.mortar,
                textOpacity: PictureScrim.ageOpacity,
                pictureIsBright: false
            ) >= 4.5)
        }
    }

    @Test("the shortcut pill's text reads at 4.5 to 1 or better over a white picture")
    func whenWhitePicture_thenPillPassesAA() {
        #expect(PictureScrim.worstCaseContrast(coverOpacity: PictureScrim.pillOpacity, textOpacity: 1) >= 4.5)
    }

    @Test("the paste count and the collection badge sit on the pill ground and pass over a white picture")
    func whenWhitePicture_thenFooterTextPassesAA() {
        let ground = PictureScrim.pillOpacity
        #expect(PictureScrim.worstCaseContrast(coverOpacity: ground, textOpacity: PictureScrim.badgeOpacity) >= 4.5)
    }

    @Test("a weaker scrim would fail, so the numbers are what keep the guarantee")
    func whenScrimTooWeak_thenContrastFails() {
        #expect(PictureScrim.worstCaseContrast(coverOpacity: 0.4, textOpacity: 1) < 4.5)
    }
}

@Suite("Picture fit")
struct PictureFitTests {
    @Test("valid pictures fill the card edge-to-edge", arguments: [
        0.3, 0.6, 0.8, 1.0, 1.35, 1.5, 1.78, 2.0, 3.0
    ])
    func whenValidAspect_thenFill(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect) == .fill)
    }

    @Test("an aspect that cannot be trusted is fitted", arguments: [0.0, -1.0, Double.nan, Double.infinity])
    func whenUnusableAspect_thenFit(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect) == .fit)
    }
}
