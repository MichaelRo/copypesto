// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Cards are covered while the screen is captured, or by hand, as the Mac covers them for a screen share")
@MainActor
struct MobileContentCoverTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    private func reveal(coversWhileCaptured: Bool) -> SecretReveal {
        SecretReveal(
            authenticator: StubUserAuthenticator(available: true, grants: true), grace: AuthenticationGrace(),
            coversWhileCaptured: coversWhileCaptured
        )
    }

    @Test("a capture covers only with the setting on, which is off by default as on the Mac; by hand always covers")
    func whenCapturedOrHidden_thenContentCoverDecides() {
        #expect(Setting.screenSharingPrivacy.defaultValue == false)
        let off = reveal(coversWhileCaptured: false)
        off.isScreenCaptured = true
        #expect(!off.isContentCovered)
        off.isHiddenByHand = true
        #expect(off.isContentCovered)

        let on = reveal(coversWhileCaptured: true)
        #expect(!on.isContentCovered)
        on.isScreenCaptured = true
        #expect(on.isContentCovered)
    }

    @Test("a covered card is concealed: no share, no drag, no edit, and its summary names only its kind")
    func whenCovered_thenTheCardOffersNoSideDoor() async throws {
        let reveal = reveal(coversWhileCaptured: true)
        let library = try await MobileTestLibrary(reveal: reveal)
        let note = try await library.add("a private address")
        reveal.isScreenCaptured = true

        let concealment = reveal.concealment(for: note)
        #expect(concealment.isConcealed)
        #expect(!concealment.allowsDrag)
        #expect(!library.state.canEditText(note))
        let summary = ClipSummary.make(note, concealment: concealment, coveredForPrivacy: true)
        #expect(!summary.title.contains("address"))
        #expect(summary.source == nil)
        #expect(library.state.copy(note), "covered is not locked: a tap still copies")
    }

    @Test("a covered secret says its kind, not its mask, until the cover is shown")
    func whenASecretIsCovered_thenItsMaskIsNotDrawn() async throws {
        let reveal = reveal(coversWhileCaptured: true)
        let library = try await MobileTestLibrary(reveal: reveal)
        try await library.service.ingest(#require(ClipCapture.text(secret)))
        let hidden = try await library.settle()
        reveal.isScreenCaptured = true

        let covered = ClipSummary.make(hidden, concealment: reveal.concealment(for: hidden), coveredForPrivacy: true)
        #expect(covered.title != hidden.gridPreview)
        #expect(covered.detail == nil)

        reveal.showUnderCover(hidden.id)
        #expect(!reveal.isCoveredForPrivacy(hidden.id))
        #expect(reveal.concealment(for: hidden).isConcealed, "the secret's own mask stays until its Show")
    }

    @Test("Show uncovers one card without asking; the cover lifting and coming back covers it again")
    func whenShownUnderCover_thenItLastsUntilTheCoverReturns() async throws {
        let reveal = reveal(coversWhileCaptured: true)
        let library = try await MobileTestLibrary(reveal: reveal)
        let first = try await library.add("first note")
        let second = try await library.add("second note")
        reveal.isScreenCaptured = true

        reveal.showUnderCover(first.id)
        #expect(!reveal.concealment(for: first).isConcealed)
        #expect(reveal.concealment(for: second).isConcealed)

        reveal.isScreenCaptured = false
        reveal.isScreenCaptured = true
        #expect(reveal.concealment(for: first).isConcealed)

        reveal.showUnderCover(first.id)
        reveal.hideAll()
        #expect(reveal.concealment(for: first).isConcealed, "leaving the foreground covers it again")
    }

    @Test("the App Switcher's picture is covered whenever the scene is not active")
    func whenNotActive_thenTheSceneIsCovered() {
        #expect(!PrivacyCoverHost.covers(in: .active))
        #expect(PrivacyCoverHost.covers(in: .inactive))
        #expect(PrivacyCoverHost.covers(in: .background))
    }
}
