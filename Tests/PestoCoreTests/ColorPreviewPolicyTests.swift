// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("ColorPreviewPolicy")
struct ColorPreviewPolicyTests {
    @Test("a parsed colour may be kept in the clear", arguments: [
        "#2F7A49", "rgb(47, 122, 73)", "hsla(141, 44%, 33%, 0.8)", "a1b2c3"
    ])
    func whenParsedColour_thenClear(preview: String) {
        #expect(ColorPreviewPolicy.mayStoreInTheClear(preview))
    }

    @Test("anything else is sealed, whatever type it was filed under", arguments: [
        "password=hunter2-Correct-Horse-Battery", "rgb(password=hunter2)", "decade", "20231234",
        "#2F7A49 and the card 4242 4242 4242 4242", "#2F7A49\nsecret",
        "# Theme tokens\nPrimary: #2F7A49\nBackground: rgb(47, 122, 73)"
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
