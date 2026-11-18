// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The GIF behind Safari's Copy Image is named by the HTML flavour")
@MainActor
struct GIFAddressTests {
    private let safariHTML = """
    <html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></head><body>\
    <img src="https://media.giphy.com/media/3o7TKsQ8/giphy.gif?cid=abc&amp;ct=g" alt="dancing basil" \
    style="-webkit-user-select: none;"></body></html>
    """

    @Test("Safari's HTML names the GIF, with its entities decoded")
    func whenSafariHTML_thenTheGIFAddress() {
        let address = ItemProviderCapture.animatedAddress(inHTML: Data(safariHTML.utf8))
        #expect(address?.absoluteString == "https://media.giphy.com/media/3o7TKsQ8/giphy.gif?cid=abc&ct=g")
    }

    @Test("a still picture, no HTML, bytes that are not text and an oversized flavour name nothing")
    func whenThereIsNoGIF_thenNil() {
        let still = "<html><body><img src=\"https://example.com/photo.jpg\"></body></html>"
        #expect(ItemProviderCapture.animatedAddress(inHTML: Data(still.utf8)) == nil)
        #expect(ItemProviderCapture.animatedAddress(inHTML: nil) == nil)
        #expect(ItemProviderCapture.animatedAddress(inHTML: Data([0xFF, 0xFE, 0xFD])) == nil)
        let huge = Data(repeating: 0x20, count: ItemProviderCapture.maxHTMLBytes + 1)
        #expect(ItemProviderCapture.animatedAddress(inHTML: huge) == nil)
    }

    @Test("the address rides on the capture and reaches ingest")
    func whenAddressIsSet_thenTheCaptureCarriesIt() throws {
        let png =
            try #require(
                Data(
                    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC"
                        + "hwGA60e6kgAAAABJRU5ErkJggg=="
                )
            )
        let capture = try #require(ClipCapture.picture(png, typeIdentifier: "public.png"))
        let address = try #require(URL(string: "https://media.giphy.com/media/x/giphy.gif"))

        #expect(capture.sourceImageURL == nil)
        #expect(capture.with(sourceImageURL: address).sourceImageURL == address)
    }
}
