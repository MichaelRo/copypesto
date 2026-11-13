// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The address of a copied GIF")
struct ImageSourceAddressTests {
    @Test("a browser's Copy Image names the picture in an img tag")
    func whenChromiumHTML_thenTheGIFAddress() {
        let html = "<meta charset='utf-8'><img src=\"https://media.example.com/cats/dance.gif\"/>"
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: html)?
            .absoluteString == "https://media.example.com/cats/dance.gif")
    }

    @Test("single quotes, a query string, upper case and extra attributes are all read")
    func whenVariants_thenStillFound() {
        #expect(ImageSourceAddress
            .animatedPictureURL(inHTML: "<img alt='x' src='https://a.example.com/x.GIF?w=200&h=100' width=3>") != nil)
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: "<IMG SRC=\"https://a.example.com/x.gif\">") != nil)
        #expect(ImageSourceAddress
            .animatedPictureURL(inHTML: "<img src=\"https://a.example.com/x.gif?w=200&amp;h=100\">")?
            .query == "w=200&h=100")
    }

    @Test("encoded entities decode in one pass without double-unescaping")
    func whenDoubleEncodedEntities_thenDecodedWithoutDoubleUnescaping() {
        let html = "<img src=\"https://a.example.com/x.gif?title=Tom&amp;amp;Jerry\">"
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: html)?.query == "title=Tom&amp;Jerry")
    }

    @Test("a browser's animation as WebP is an address to fetch; a Google Images thumbnail, which is a still, is not")
    func whenWebPOrThumbnail_thenOnlyWebPIsNamed() {
        let giphy = "<img src=\"https://media0.giphy.com/media/abc/giphy.webp?cid=1&amp;ct=g\"/>"
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: giphy)?.pathExtension == "webp")
        let thumbnail = "<meta charset='utf-8'><img src=\"https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcS&amp;s=10\" alt=\"a cat\"/>"
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: thumbnail) == nil)
    }

    @Test("a picture that is not a GIF, a data address, an insecure address and a missing tag give nothing")
    func whenNotAGIF_thenNil() {
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: "<img src=\"https://a.example.com/x.png\">") == nil)
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: "<img src=\"data:image/gif;base64,R0lGOD\">") == nil)
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: "<img src=\"http://a.example.com/x.gif\">") == nil)
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: "<p>no picture</p>") == nil)
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: "") == nil)
    }

    @Test("an address that would not be fetched for a link preview is not fetched for this either")
    func whenNotEligible_thenNil() {
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: "<img src=\"https://localhost/x.gif\">") == nil)
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: "<img src=\"https://192.168.1.5/x.gif\">") == nil)
        #expect(ImageSourceAddress
            .animatedPictureURL(inHTML: "<img src=\"https://a.example.com/x.gif?token=abc\">") == nil)
        #expect(ImageSourceAddress
            .animatedPictureURL(inHTML: "<img src=\"https://user:pw@a.example.com/x.gif\">") == nil)
    }

    @Test("with several pictures the first GIF is the one")
    func whenSeveral_thenFirstGIF() {
        let html = "<img src=\"https://a.example.com/a.png\"><img src=\"https://b.example.com/b.gif\"><img src=\"https://c.example.com/c.gif\">"
        #expect(ImageSourceAddress.animatedPictureURL(inHTML: html)?.host == "b.example.com")
    }

    @Test("a huge page is not read past its start")
    func whenHuge_thenBounded() {
        let filler = String(repeating: "x", count: 600_000)
        #expect(ImageSourceAddress
            .animatedPictureURL(inHTML: filler + "<img src=\"https://a.example.com/x.gif\">") == nil)
    }
}
