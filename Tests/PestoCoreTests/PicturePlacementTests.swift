// SPDX-License-Identifier: MIT
import CoreGraphics
import Testing
@testable import PestoCore

@Suite("Picture placement (ADR 0080)")
struct PicturePlacementTests {
    private let medium = CGSize(width: 180, height: 160)
    private let keyboard = CGSize(width: 150, height: 88)

    // MARK: - Fill or fit

    @Test("a photo near the Mac card's shape still fills it, as ADR 0041 had it", arguments: [0.8, 1.0, 1.33, 1.35])
    func whenPhotoNearTheCardShape_thenFill(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect) == .fill)
    }

    @Test("the ranges are measured against the card's own shape, so a wide keyboard card fills a 16:9 photo")
    func whenTheCardIsWide_thenTheRangeMovesWithIt() {
        let cardAspect = Double(keyboard.width / keyboard.height)
        #expect(PictureFit.decide(aspectRatio: 16.0 / 9.0, cardAspect: cardAspect) == .fill)
        #expect(PictureFit.decide(aspectRatio: 1.0, cardAspect: cardAspect) == .fit)
    }

    @Test("a screen capture fills only when filling crops a tenth of it or less", arguments: [
        (1.0, PictureFit.fit), (1.05, .fill), (1.125, .fill), (1.24, .fill), (1.3, .fit), (0.8, .fit)
    ])
    func whenScreenCapture_thenTheBandIsNarrow(aspect: Double, expected: PictureFit) {
        #expect(PictureFit.decide(aspectRatio: aspect, isScreenCapture: true) == expected)
    }

    @Test("a GIF uses the wider animated range on every surface", arguments: [0.5625, 1.0, 1.78])
    func whenAnimated_thenTheAnimatedRange(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect, isAnimated: true) == .fill)
    }

    @Test("a very tall picture (a receipt, a whole page) fills from its top", arguments: [0.1, 0.25, 0.39])
    func whenVeryTall_thenFillFromTop(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect) == .fillFromTop)
        #expect(PictureFit.decide(aspectRatio: aspect, isScreenCapture: true) == .fillFromTop)
    }

    @Test("a phone screenshot and a panorama are shown whole", arguments: [0.4615, 0.5625, 0.75, 1.78, 3.0, 6.0])
    func whenTallOrWideButReadable_thenFit(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect) == .fit)
    }

    @Test("a picture smaller than the card is never filled", arguments: [
        CGSize(width: 64, height: 64),
        CGSize(width: 120, height: 100)
    ])
    func whenSmallerThanTheCard_thenFit(pixels: CGSize) {
        #expect(PictureFit.decide(aspectRatio: 1.1, pixelSize: pixels, card: medium) == .fit)
    }

    @Test("a picture as large as the card fills as usual")
    func whenAsLargeAsTheCard_thenFill() {
        #expect(PictureFit.decide(aspectRatio: 1.1, pixelSize: CGSize(width: 330, height: 300), card: medium) == .fill)
    }

    @Test("an aspect that cannot be trusted is fitted", arguments: [0.0, -1.0, Double.nan, Double.infinity])
    func whenUnusableAspect_thenFit(aspect: Double) {
        #expect(PictureFit.decide(aspectRatio: aspect) == .fit)
    }

    // MARK: - Where a fitted picture sits

    @Test("a tall picture takes the whole height but the last 18 points, from the top")
    func whenTallFitted_thenItKeepsOnlyTheMinimumBand() {
        let frame = PictureFrame.fitted(aspectRatio: 0.4615, in: medium, footerBand: 36)
        #expect(abs(frame.height - 142) < 0.01)
        #expect(frame.minY == 0)
        #expect(abs(frame.midX - 90) < 0.01)
    }

    @Test("a wide picture keeps the full width and sits just above the footer band")
    func whenWideFitted_thenItClearsTheFooter() {
        let frame = PictureFrame.fitted(aspectRatio: 16.0 / 9.0, in: medium, footerBand: 36)
        #expect(abs(frame.width - 180) < 0.01)
        #expect(abs(frame.maxY - (160 - 36)) < 0.01)
    }

    @Test("a panorama with room to spare is centered, the footer band still clear")
    func whenSlackIsLarge_thenCentered() {
        let frame = PictureFrame.fitted(aspectRatio: 6, in: medium, footerBand: 36)
        let below = 160 - frame.maxY
        #expect(abs(frame.minY - below) < 0.01)
        #expect(below >= 36)
    }

    @Test("a title adds to the band a wide picture clears")
    func whenTitled_thenTheBandGrows() {
        let frame = PictureFrame.fitted(aspectRatio: 16.0 / 9.0, in: medium, footerBand: 56)
        #expect(abs(frame.maxY - (160 - 56)) < 0.01)
    }

    @Test("a small picture is drawn at most twice its pixel size, centered")
    func whenSmall_thenAtMostTwice() {
        let frame = PictureFrame.fitted(
            aspectRatio: 1, in: medium, footerBand: 36, pixelSize: CGSize(width: 32, height: 32)
        )
        #expect(frame.size == CGSize(width: 64, height: 64))
        #expect(abs(frame.midX - 90) < 0.01)
    }

    @Test("pixel art is drawn with hard edges, a photo smoothly", arguments: [
        (CGSize(width: 16, height: 16), true), (CGSize(width: 64, height: 48), true),
        (CGSize(width: 65, height: 40), false), (CGSize(width: 1920, height: 1080), false)
    ])
    func whenTiny_thenSharpPixels(pixels: CGSize, sharp: Bool) {
        #expect(PictureFrame.drawsPixelsSharp(pixelSize: pixels) == sharp)
    }

    @Test("a frame never escapes the card", arguments: [0.05, 0.3, 0.7, 1.0, 1.5, 3.0, 20.0])
    func whenAnyAspect_thenInsideTheCard(aspect: Double) {
        let frame = PictureFrame.fitted(aspectRatio: aspect, in: keyboard, footerBand: 28)
        #expect(CGRect(origin: .zero, size: keyboard).insetBy(dx: -0.01, dy: -0.01).contains(frame))
        #expect(frame.height <= keyboard.height - PictureFrame.minimumBand + 0.01)
    }

    // MARK: - Screen captures

    @Test("the screenshot tools are known by bundle identifier", arguments: [
        "com.apple.screencaptureui", "com.apple.Screenshot", "pl.maketheweb.cleanshotx", "cc.ffitch.shottr"
    ])
    func whenAScreenshotTool_thenACapture(bundleID: String) {
        #expect(ScreenCaptureApps.isCapture(sourceBundleID: bundleID))
    }

    @Test("other apps and no app are not screen captures", arguments: [
        Optional("com.apple.Safari"), Optional("com.apple.Photos"), nil
    ])
    func whenAnotherApp_thenNotACapture(bundleID: String?) {
        #expect(!ScreenCaptureApps.isCapture(sourceBundleID: bundleID))
    }
}
