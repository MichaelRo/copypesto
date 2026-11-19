// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("A decoded token leaves only through Copy Payload, and only while it is safe to show")
@MainActor
struct JWTSideDoorTests {
    private static let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJzdWIiOiJwZXN0byIsIm5hbWUiOiJBZGEgTG92ZWxhY2UifQ.c2lnbmF0dXJlLWJ5dGVz"

    private func decoded(coversWhileCaptured: Bool = true) async throws
    -> (MobileTestLibrary, ClipboardItem) {
        let reveal = SecretReveal(
            authenticator: StubUserAuthenticator(available: true, grants: true), grace: AuthenticationGrace(),
            coversWhileCaptured: coversWhileCaptured
        )
        let library = try await MobileTestLibrary(reveal: reveal)
        library.state.isActivated = true
        try await library.service.ingest(#require(ClipCapture.text(Self.token)))
        let item = try await library.settle()
        #expect(await library.state.decodeJWT(item) != nil)
        #expect(library.state.decodedJWT != nil)
        return (library, item)
    }

    @Test("Hide Clip Contents closes the decoded token")
    func whenContentsAreHiddenByHand_thenTheDecodeCloses() async throws {
        let (library, _) = try await decoded()
        library.state.secretReveal.isHiddenByHand = true
        #expect(library.state.decodedJWT == nil)
    }

    @Test("a screen capture closes the decoded token when the cover setting is on, and not when it is off")
    func whenTheScreenIsCaptured_thenTheDecodeClosesOnlyWithTheCoverOn() async throws {
        let (covering, _) = try await decoded()
        covering.state.secretReveal.isScreenCaptured = true
        #expect(covering.state.decodedJWT == nil)

        let (uncovered, _) = try await decoded(coversWhileCaptured: false)
        uncovered.state.secretReveal.isScreenCaptured = true
        #expect(uncovered.state.decodedJWT != nil)
    }

    @Test("a token decoded while the history locks or Pesto is away is never kept")
    func whenTheAnswerArrivesAfterTheLockOrWhileAway_thenNothingIsHeld() async throws {
        let (library, item) = try await decoded()
        library.state.decodedJWT = nil
        library.state.isActivated = false
        #expect(await library.state.decodeJWT(item) == nil)
        #expect(library.state.decodedJWT == nil)
    }
}
