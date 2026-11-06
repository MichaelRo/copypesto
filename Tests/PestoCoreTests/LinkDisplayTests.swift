// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Link display")
struct LinkDisplayTests {
    @Test("a plain address splits into its host and its path")
    func whenPlainURL_thenHostAndRest() {
        let link = LinkDisplay.parse("https://example.com/docs/page")
        #expect(link == LinkDisplay(host: "example.com", rest: "/docs/page"))
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
        (3, 24.0), (24, 24.0), (25, 18.0), (80, 18.0)
    ])
    func whenHostLength_thenFixedPoints(length: Int, points: Double) {
        #expect(LinkDisplay.hostPoints(forLength: length) == points)
    }

    @Test(
        "the host takes the lines it fits and the path the room left, the path dropping out before the host shrinks",
        arguments: [
            (24.0, 2, 11.0, 104.0, [2, 2]), (18.0, 3, 11.0, 104.0, [3, 2]), (24.0 * 0.85, 2, 11.0 * 0.85, 64.0, [2, 0]),
            (18.0 * 0.85, 3, 11.0 * 0.85, 64.0, [3, 0]), (24.0, 2, 11.0, 40.0, [1, 0])
        ]
    )
    func whenBudget_thenLinesShared(host: Double, hostMost: Int, path: Double, budget: Double, expected: [Int]) {
        let lines = LinkDisplay.lineLimits(
            hostPoints: host, hostMaxLines: hostMost, pathPoints: path, heightBudget: budget
        )
        #expect([lines.host, lines.path] == expected)
    }

    @Test("a host may break after each dot, so a long one wraps instead of being cut")
    func whenHostWraps_thenBreaksAfterDots() {
        #expect(LinkDisplay.breakableHost("news.example.com") == "news.\u{200B}example.\u{200B}com")
    }

    @Test("a query or fragment is never shown, so a token in a link stays out of sight at rest")
    func whenQueryAndFragment_thenNeitherIsDisplayed() {
        let link = LinkDisplay.parse("https://example.com/reset/start?token=s3cr3t&u=1#frag-secret")
        #expect(link == LinkDisplay(host: "example.com", rest: "/reset/start"))
        let all = (link?.host ?? "") + (link?.rest ?? "")
        #expect(!all.contains("s3cr3t") && !all.contains("token") && !all.contains("frag"))
        #expect(LinkDisplay.parse("https://example.com/?token=abc")?.rest.isEmpty == true)
    }

    @Test("a very long path is cut to a fixed length with an ellipsis")
    func whenLongPath_thenCapped() {
        let rest = LinkDisplay.parse("https://example.com/" + String(repeating: "a", count: 500))?.rest
        #expect(rest?.count == LinkDisplay.restLimit)
        #expect(rest?.hasSuffix("\u{2026}") == true)
    }

    @Test("an IPv6 host keeps its brackets, so a port after it is not part of the address")
    func whenIPv6_thenBracketed() {
        #expect(LinkDisplay.parse("http://[::1]:8080/x") == LinkDisplay(host: "[::1]", rest: ":8080/x"))
        #expect(LinkDisplay.parse("http://[2001:db8::7]/x")?.host == "[2001:db8::7]")
    }
}
