// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("LinkOpenPolicy")
struct LinkOpenPolicyTests {
    @Test("a web address opens in the browser", arguments: [
        "https://example.com/a?b=c", "http://example.com", "  HTTPS://Example.com/x  \n"
    ])
    func whenWebAddress_thenBrowser(text: String) {
        let action = LinkOpenPolicy.action(for: text)
        guard case let .openInBrowser(url) = action else {
            Issue.record("got \(action)")
            return
        }
        #expect(url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http")
    }

    @Test("a file address is shown in Finder, never opened")
    func whenFileAddress_thenReveal() {
        let action = LinkOpenPolicy.action(for: "file:///Applications/Foo.app")
        #expect(action == .revealInFinder(URL(filePath: "/Applications/Foo.app")))
    }

    @Test("anything else does nothing", arguments: [
        "", "javascript:alert(1)", "ftp://example.com/a", "x-apple.systempreferences:com.apple.Settings",
        "smb://server/share", "https://", "not a link", "file://"
    ])
    func whenOtherScheme_thenNothing(text: String) {
        #expect(LinkOpenPolicy.action(for: text) == .none)
    }
}
