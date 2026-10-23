// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("URLRedirectUnwrapper")
struct URLRedirectUnwrapperTests {
    @Test("unwraps Google search result redirect with q parameter")
    func whenGoogleURLWithQParam_thenUnwraps() throws {
        let original = try #require(
            URL(string: "https://www.google.com/url?q=https://en.wikipedia.org/wiki/Pesto&sa=U&ved=2ahUKEwj")
        )
        let unwrapped = URLRedirectUnwrapper.unwrap(original)
        #expect(unwrapped.absoluteString == "https://en.wikipedia.org/wiki/Pesto")
    }

    @Test("unwraps Google search result redirect with url parameter")
    func whenGoogleURLWithUrlParam_thenUnwraps() throws {
        let original = try #require(
            URL(string: "https://www.google.com/url?url=https://github.com/apple/swift&rct=j&q=&esrc=s")
        )
        let unwrapped = URLRedirectUnwrapper.unwrap(original)
        #expect(unwrapped.absoluteString == "https://github.com/apple/swift")
    }

    @Test("unwraps international Google domains")
    func whenInternationalGoogleDomain_thenUnwraps() throws {
        let original = try #require(URL(string: "https://www.google.co.uk/url?q=https://example.com/page"))
        let unwrapped = URLRedirectUnwrapper.unwrap(original)
        #expect(unwrapped.absoluteString == "https://example.com/page")
    }

    @Test("unwraps Outlook Safelinks")
    func whenOutlookSafelink_thenUnwraps() throws {
        let original = try #require(
            URL(
                string: "https://nam02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2Freport&data=04"
            )
        )
        let unwrapped = URLRedirectUnwrapper.unwrap(original)
        #expect(unwrapped.absoluteString == "https://example.com/report")
    }

    @Test("leaves normal URLs unchanged")
    func whenNormalURL_thenLeavesUnchanged() throws {
        let url = try #require(URL(string: "https://copypesto.net"))
        #expect(URLRedirectUnwrapper.unwrap(url) == url)
    }

    @Test("leaves non-redirect Google URLs unchanged")
    func whenNonRedirectGoogleURL_thenLeavesUnchanged() throws {
        let url = try #require(URL(string: "https://www.google.com/search?q=pesto"))
        #expect(URLRedirectUnwrapper.unwrap(url) == url)
    }
}
