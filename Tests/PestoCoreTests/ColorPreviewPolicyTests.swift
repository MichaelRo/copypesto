// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("ColorPreviewPolicy")
struct ColorPreviewPolicyTests {
    @Test("a parsed colour may be kept in the clear", arguments: [
        "#2F7A49", "rgb(47, 122, 73)", "hsla(141, 44%, 33%, 0.8)", "a1b2c3",
        "oklch(0.517 0.114 150.2)", "oklab(0.6 -0.1 0.1)", "hwb(141 18% 52%)",
        "color(display-p3 0.2 0.5 0.3)", "color(srgb 0.184 0.478 0.286)", "cmyk(61%, 0%, 40%, 52%)"
    ])
    func whenParsedColour_thenClear(preview: String) {
        #expect(ColorPreviewPolicy.mayStoreInTheClear(preview))
    }

    @Test("anything else is sealed, whatever type it was filed under", arguments: [
        "password=hunter2-Correct-Horse-Battery", "rgb(password=hunter2)", "decade", "20231234",
        "#2F7A49 and the card 4242 4242 4242 4242", "#2F7A49\nsecret",
        "# Theme tokens\nPrimary: #2F7A49\nBackground: rgb(47, 122, 73)",
        "oklch(password=123)", "oklab(secret=abc)", "hwb(token=xyz)", "color(display-p3 key=1)",
        "color(--custom 1 0 0)", "cmyk(1, 2, 3, 4)", "red", "rebeccapurple", "0xFF00AA",
        "Color(red: 1, green: 0, blue: 0)", "oklch(from #fff l c h)", "oklch(0.5, 0.1, 150)",
        "hwb(120 1 2)"
    ])
    func whenNotAColour_thenSealed(preview: String) {
        #expect(!ColorPreviewPolicy.mayStoreInTheClear(preview))
        #expect(ContentClassifier.classify(text: preview).type != .color)
    }

    @Test("a colour literal longer than 64 characters is sealed")
    func whenTooLong_thenSealed() {
        let long = "rgb(" + String(repeating: "0", count: 70) + ", 0, 0)"
        #expect(!ColorPreviewPolicy.mayStoreInTheClear(long))
    }
}
