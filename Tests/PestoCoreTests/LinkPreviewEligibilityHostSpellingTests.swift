// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Spellings of a private host that a link preview must refuse")
struct LinkPreviewEligibilityHostSpellingTests {
    private func eligible(_ text: String) -> Bool {
        LinkPreviewEligibility.isEligible(URL(string: text) ?? URL(fileURLWithPath: "/"))
    }

    @Test("a trailing dot, upper case, a zero address and an IPv4-mapped IPv6 address are all refused", arguments: [
        "http://localhost./", "http://LOCALHOST/", "http://0.0.0.0/", "http://[::ffff:127.0.0.1]/",
        "http://127.0.0.1./", "http://printer.LOCAL/", "http://01.02.03.04/", "http://256.1.1.1/"
    ])
    func whenOddSpelling_thenRefused(url: String) {
        #expect(!eligible(url), "\(url)")
    }

    @Test("internationalised and hyphenated public names are still fetched", arguments: [
        "https://xn--caf-dma.example/", "https://my-site.example.co.uk/page", "https://a.b.c.example.com/"
    ])
    func whenPublicName_thenFetched(url: String) {
        #expect(eligible(url), "\(url)")
    }
}
