// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("A download follows a redirect only to an address a preview may fetch")
struct BoundedDownloadRedirectTests {
    @Test("a hop is judged like the first request", arguments: [
        ("https://cdn.example.com/a.gif", true),
        ("http://127.0.0.1/admin", false),
        ("http://192.168.0.1/", false),
        ("http://127.1/", false),
        ("https://example.com/reset?token=abc", false),
        ("file:///etc/passwd", false)
    ])
    func whenRedirected_thenTheTargetIsJudged(url: String, allowed: Bool) {
        #expect(BoundedDownload.allowsRedirect(to: URL(string: url)) == allowed, "\(url)")
    }

    @Test("a redirect with no address is refused")
    func whenNoTarget_thenRefused() {
        #expect(!BoundedDownload.allowsRedirect(to: nil))
    }
}
