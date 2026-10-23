// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Showing the real content of a hidden clip")
struct HiddenClipRevealTests {
    @Test("an ordinary clip needs no authentication")
    func whenNotHidden_thenPermitted() async {
        let refusing = StubUserAuthenticator(available: true, grants: false)
        #expect(await HiddenClipReveal.permitted(
            isHidden: false,
            using: refusing,
            reason: "x",
            grace: AuthenticationGrace()
        ))
    }

    @Test("a hidden clip is shown only after Touch ID or the account password")
    func whenHidden_thenNeedsAuthentication() async {
        #expect(await HiddenClipReveal.permitted(
            isHidden: true, using: StubUserAuthenticator(available: true, grants: true), reason: "x",
            grace: AuthenticationGrace()
        ))
        #expect(await !HiddenClipReveal.permitted(
            isHidden: true, using: StubUserAuthenticator(available: true, grants: false), reason: "x",
            grace: AuthenticationGrace()
        ))
    }

    @Test("a Mac that cannot authenticate at all cannot show a hidden clip: it fails closed")
    func whenNothingCanAuthenticate_thenRefused() async {
        #expect(await !HiddenClipReveal.permitted(
            isHidden: true, using: StubUserAuthenticator(available: false, grants: false), reason: "x",
            grace: AuthenticationGrace()
        ))
    }

    @Test("a revealed clip shows the start of its text, and nothing when the payload is not text")
    func readableText_isTheStartOfTheText() {
        #expect(HiddenClipReveal.readableText(from: Data("4242 4242 4242 4242".utf8)) == "4242 4242 4242 4242")
        #expect(HiddenClipReveal.readableText(from: Data(String(repeating: "a", count: 900).utf8))?.count == 500)
        #expect(HiddenClipReveal.readableText(from: Data([0xFF, 0xFE, 0x00])) == nil)
        #expect(HiddenClipReveal.readableText(from: nil) == nil)
    }
}
