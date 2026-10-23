// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The address of a copied GIF")
struct ImageSourceAddressTests {
    @Test("a browser's Copy Image names the picture in an img tag")
    func whenChromiumHTML_thenTheGIFAddress() {
        let html = "<meta charset='utf-8'><img src=\"https://media.example.com/cats/dance.gif\"/>"
        #expect(ImageSourceAddress.gifURL(inHTML: html)?.absoluteString == "https://media.example.com/cats/dance.gif")
    }

    @Test("single quotes, a query string, upper case and extra attributes are all read")
    func whenVariants_thenStillFound() {
        #expect(ImageSourceAddress
            .gifURL(inHTML: "<img alt='x' src='https://a.example.com/x.GIF?w=200&h=100' width=3>") != nil)
        #expect(ImageSourceAddress.gifURL(inHTML: "<IMG SRC=\"https://a.example.com/x.gif\">") != nil)
    }

    @Test("a picture that is not a GIF, a data address, an insecure address and a missing tag give nothing")
    func whenNotAGIF_thenNil() {
        #expect(ImageSourceAddress.gifURL(inHTML: "<img src=\"https://a.example.com/x.png\">") == nil)
        #expect(ImageSourceAddress.gifURL(inHTML: "<img src=\"data:image/gif;base64,R0lGOD\">") == nil)
        #expect(ImageSourceAddress.gifURL(inHTML: "<img src=\"http://a.example.com/x.gif\">") == nil)
        #expect(ImageSourceAddress.gifURL(inHTML: "<p>no picture</p>") == nil)
        #expect(ImageSourceAddress.gifURL(inHTML: "") == nil)
    }

    @Test("an address that would not be fetched for a link preview is not fetched for this either")
    func whenNotEligible_thenNil() {
        #expect(ImageSourceAddress.gifURL(inHTML: "<img src=\"https://localhost/x.gif\">") == nil)
        #expect(ImageSourceAddress.gifURL(inHTML: "<img src=\"https://192.168.1.5/x.gif\">") == nil)
        #expect(ImageSourceAddress.gifURL(inHTML: "<img src=\"https://a.example.com/x.gif?token=abc\">") == nil)
        #expect(ImageSourceAddress.gifURL(inHTML: "<img src=\"https://user:pw@a.example.com/x.gif\">") == nil)
    }

    @Test("with several pictures the first GIF is the one")
    func whenSeveral_thenFirstGIF() {
        let html = "<img src=\"https://a.example.com/a.png\"><img src=\"https://b.example.com/b.gif\"><img src=\"https://c.example.com/c.gif\">"
        #expect(ImageSourceAddress.gifURL(inHTML: html)?.host == "b.example.com")
    }

    @Test("a huge page is not read past its start")
    func whenHuge_thenBounded() {
        let filler = String(repeating: "x", count: 600_000)
        #expect(ImageSourceAddress.gifURL(inHTML: filler + "<img src=\"https://a.example.com/x.gif\">") == nil)
    }
}
