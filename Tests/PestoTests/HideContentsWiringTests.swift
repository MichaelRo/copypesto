// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("HideContentsWiring", .serialized)
    @MainActor
    final class HideContentsWiringTests {
        @Test("toggling Hide Clip Contents clears revealed secrets generation and activates CardConcealment")
        func whenHideContentsToggled_thenRevealedSecretClearsAndCardConcealmentActivates() {
            let delegate = AppDelegate()
            let state = delegate.appState

            #expect(!state.isContentHiddenManually)
            #expect(!state.isContentCovered(screenSharingPrivacy: false))

            delegate.statusToggleContentHidden()

            #expect(state.isContentHiddenManually)
            let covered = state.isContentCovered(screenSharingPrivacy: false)
            #expect(covered)

            let card = ClipboardCard(
                item: ClipboardItem(
                    type: .text,
                    previewText: "••••1234",
                    sensitivity: .apiKey,
                    contentHash: UUID().uuidString,
                    byteSize: 12,
                    deviceID: "test",
                    sequenceNumber: 1
                ),
                isPrivacyBlurred: covered,
                hideSecretsGeneration: 1
            )
            #expect(card.isCoveredForPrivacy)
            #expect(card.concealment.isConcealed)
            #expect(!card.concealment.allowsDecode)
            #expect(!card.concealment.allowsHoverDetail)
            #expect(!card.concealment.allowsQuickLook)
            #expect(!card.concealment.allowsAIActions)
            #expect(!card.concealment.allowsDrag)
            #expect(card.revealedSecret == nil)

            delegate.statusToggleContentHidden()
            #expect(!state.isContentHiddenManually)
        }
    }
}
