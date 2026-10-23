// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("ClipSizePolicy")
struct ClipSizePolicyTests {
    private let megabyte = 1_048_576

    @Test("text-like copies are limited to 10 MB", arguments: [
        "public.utf8-plain-text", "public.plain-text", "public.rtf", "public.html", "public.url", "public.file-url"
    ])
    func whenTextLike_thenLimitIsTenMegabytes(type: String) {
        #expect(ClipSizePolicy.limit(forTypeIdentifier: type) == 10 * megabyte)
    }

    @Test(
        "pictures and other data are limited to 100 MB",
        arguments: ["public.png", "public.tiff", "com.compuserve.gif", "com.adobe.pdf"]
    )
    func whenOtherData_thenLimitIsOneHundredMegabytes(type: String) {
        #expect(ClipSizePolicy.limit(forTypeIdentifier: type) == 100 * megabyte)
    }

    @Test("a copy at the limit is kept and one byte over is refused")
    func whenAtTheLimit_thenKept() {
        let type = "public.utf8-plain-text"
        #expect(!ClipSizePolicy.isTooLarge(byteCount: 10 * megabyte, typeIdentifier: type))
        #expect(ClipSizePolicy.isTooLarge(byteCount: 10 * megabyte + 1, typeIdentifier: type))
    }

    @Test("the message says what was refused, the size and the limit, in plain words")
    func whenTooLarge_thenTheMessageNamesTheSizeAndTheLimit() {
        let message = ClipSizePolicy.message(byteCount: 62 * megabyte, typeIdentifier: "public.utf8-plain-text")
        #expect(message == "The last copy is 62 MB, over the 10 MB Pesto keeps for text, so it was not saved.")
    }

    @Test("the message for a picture says picture, not text")
    func whenAPictureIsTooLarge_thenTheMessageSaysPicture() {
        let message = ClipSizePolicy.message(byteCount: 150 * megabyte, typeIdentifier: "public.tiff")
        #expect(message ==
            "The last copy is 150 MB, over the 100 MB Pesto keeps for pictures and files, so it was not saved.")
    }
}
