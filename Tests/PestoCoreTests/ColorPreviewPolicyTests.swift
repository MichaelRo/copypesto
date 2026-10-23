// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("ColorPreviewPolicy")
struct ColorPreviewPolicyTests {
    @Test("a parsed colour may be kept in the clear", arguments: [
        "#FF5733", "rgb(255, 87, 51)", "hsla(10, 100%, 60%, 0.8)", "a1b2c3"
    ])
    func whenParsedColour_thenClear(preview: String) {
        #expect(ColorPreviewPolicy.mayStoreInTheClear(preview))
    }

    @Test("anything else is sealed, whatever type it was filed under", arguments: [
        "password=hunter2-Correct-Horse-Battery", "rgb(password=hunter2)", "decade", "20231234",
        "#FF5733 and the card 4242 4242 4242 4242", "#FF5733\nsecret"
    ])
    func whenNotAColour_thenSealed(preview: String) {
        #expect(!ColorPreviewPolicy.mayStoreInTheClear(preview))
    }

    @Test("a colour literal longer than 64 characters is sealed")
    func whenTooLong_thenSealed() {
        let long = "rgb(" + String(repeating: "0", count: 70) + ", 0, 0)"
        #expect(!ColorPreviewPolicy.mayStoreInTheClear(long))
    }
}
