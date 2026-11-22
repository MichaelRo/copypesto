// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

extension MobilePasteboardGlobals {
    @Suite("Showing a hidden clip")
    @MainActor
    struct SecretRevealTests {
        private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

        @Test("Show asks first, and a refusal keeps the clip hidden")
        func whenAuthenticationFails_thenTheClipStaysHidden() async {
            let reveal = SecretReveal(
                authenticator: StubUserAuthenticator(available: true, grants: false), grace: AuthenticationGrace()
            )
            let id = UUID()
            #expect(await !reveal.show(id, reason: "test"))
            #expect(!reveal.isShown(id))
        }

        @Test("inside the authentication window Show does not ask again")
        func whenGraceIsOpen_thenShowDoesNotAsk() async {
            let grace = AuthenticationGrace()
            grace.record()
            let reveal = SecretReveal(
                authenticator: StubUserAuthenticator(available: true, grants: false),
                grace: grace
            )
            let id = UUID()
            #expect(await reveal.show(id, reason: "test"))
            #expect(reveal.isShown(id))
        }

        @Test("everything shown hides again when Pesto leaves the foreground")
        func whenLeavingTheForeground_thenAllHide() async throws {
            let library = try await MobileTestLibrary()
            let id = UUID()
            await library.state.secretReveal.show(id, reason: "test")
            #expect(library.state.secretReveal.isShown(id))

            library.state.didLeaveForeground()

            #expect(!library.state.secretReveal.isShown(id))
        }

        @Test("a secret is covered until shown, its row says only its mask, and Copy still writes the real text")
        func whenASecretIsAdded_thenItIsCoveredButCopyable() async throws {
            let library = try await MobileTestLibrary()
            try await library.service.ingest(#require(ClipCapture.text(secret)))
            let item = try await library.settle()
            #expect(item.sensitivityRaw != nil)

            let covered = library.state.secretReveal.concealment(for: item, nsfwMode: .blur)
            #expect(covered.isConcealed)
            #expect(!covered.allowsDrag)
            let summary = ClipSummary.make(item, concealment: covered)
            #expect(summary.isCovered)
            #expect(!summary.title.contains(secret))

            #expect(library.state.copy(item))
            #expect(AppPasteboard.general.string == secret)

            await library.state.secretReveal.show(item.id, reason: "test")
            #expect(!library.state.secretReveal.concealment(for: item, nsfwMode: .blur).isConcealed)
        }

        @Test("an explicit clip can be revealed on iOS and blurs again on Hide or leaving the foreground")
        func whenNSFWClipIsShown_thenItUncoversUntilHiddenOrForeground() async throws {
            let library = try await MobileTestLibrary()
            let item = try await library.add("explicit pic")
            item.isNSFW = true

            #expect(library.state.secretReveal.concealment(for: item, nsfwMode: .blur).isConcealed)
            #expect(library.state.secretReveal.concealment(for: item, nsfwMode: .blur).isNSFWBlurred)

            library.state.secretReveal.showNSFW(item.id)
            #expect(library.state.secretReveal.isNSFWShown(item.id))
            #expect(!library.state.secretReveal.concealment(for: item, nsfwMode: .blur).isConcealed)

            library.state.secretReveal.hideNSFW(item.id)
            #expect(!library.state.secretReveal.isNSFWShown(item.id))
            #expect(library.state.secretReveal.concealment(for: item, nsfwMode: .blur).isConcealed)

            library.state.secretReveal.showNSFW(item.id)
            library.state.didLeaveForeground()
            #expect(!library.state.secretReveal.isNSFWShown(item.id))
            #expect(library.state.secretReveal.concealment(for: item, nsfwMode: .blur).isConcealed)
        }

        @Test("pending image waits behind checking cover when explicit filtering is on, and shows immediately when off")
        func whenImageAnalysisPending_thenPendingCoverRespectsNSFWMode() async throws {
            let library = try await MobileTestLibrary()
            let item = try await library.add("pending-gif")
            item.typeRaw = ClipboardType.image.rawValue
            item.analysisPending = true

            #expect(library.state.secretReveal.concealment(for: item, nsfwMode: .blur).isConcealed)
            #expect(library.state.secretReveal.concealment(for: item, nsfwMode: .hide).isConcealed)
            #expect(!library.state.secretReveal.concealment(for: item, nsfwMode: .show).isConcealed)
        }
    }
}
