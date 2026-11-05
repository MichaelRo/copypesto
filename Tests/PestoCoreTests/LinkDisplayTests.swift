// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Link display")
struct LinkDisplayTests {
    @Test("a plain address splits into its host and the rest")
    func whenPlainURL_thenHostAndRest() {
        let link = LinkDisplay.parse("https://example.com/docs/page?id=7#top")
        #expect(link == LinkDisplay(host: "example.com", rest: "/docs/page?id=7#top"))
    }

    @Test("the root path is not shown")
    func whenRootPath_thenRestIsEmpty() {
        #expect(LinkDisplay.parse("https://example.com/")?.rest.isEmpty == true)
        #expect(LinkDisplay.parse("https://example.com")?.rest.isEmpty == true)
    }

    @Test("a name before an at sign is the user info, never the host a person sees")
    func whenUserInfo_thenHostIsTheRealOne() {
        let link = LinkDisplay.parse("https://paypal.com@evil.example/login")
        #expect(link?.host == "evil.example")
        #expect(link?.rest == "/login")
    }

    @Test("a port stays with the rest and out of the host")
    func whenPort_thenPortLeadsTheRest() {
        let link = LinkDisplay.parse("http://localhost:8080/a")
        #expect(link == LinkDisplay(host: "localhost", rest: ":8080/a"))
    }

    @Test("a host is shown in lower case")
    func whenMixedCase_thenLowercased() {
        #expect(LinkDisplay.parse("HTTPS://Example.COM/Path")?.host == "example.com")
        #expect(LinkDisplay.parse("HTTPS://Example.COM/Path")?.rest == "/Path")
    }

    @Test("an address typed without a scheme still has a host")
    func whenNoScheme_thenHostFound() {
        #expect(LinkDisplay.parse("example.com/a")?.host == "example.com")
    }

    @Test("an international host is kept as one non-empty host")
    func whenInternationalHost_thenHostPresent() {
        let host = LinkDisplay.parse("https://münchen.de/karte")?.host
        #expect(host == "münchen.de" || host == "xn--mnchen-3ya.de")
    }

    @Test("addresses with no host give nothing, so the card keeps its usual look", arguments: [
        "mailto:someone@example.com", "tel:+15551234", "file:///Users/me/a.txt", "not a link", "", "https://"
    ])
    func whenNoHost_thenNil(text: String) {
        #expect(LinkDisplay.parse(text) == nil)
    }

    @Test("text with a line break in it is not one link")
    func whenMultiline_thenNil() {
        #expect(LinkDisplay.parse("https://a.example\nhttps://b.example") == nil)
    }

    @Test("the host is set at a fixed size by its length, never fitted to a measurement", arguments: [
        (3, 22.0), (14, 22.0), (15, 17.0), (22, 17.0), (23, 15.0), (80, 15.0)
    ])
    func whenHostLength_thenFixedPoints(length: Int, points: Double) {
        #expect(LinkDisplay.hostPoints(forLength: length) == points)
    }

    @Test("a host may break after each dot, so a long one wraps instead of being cut")
    func whenHostWraps_thenBreaksAfterDots() {
        #expect(LinkDisplay.breakableHost("news.example.com") == "news.\u{200B}example.\u{200B}com")
    }
}
