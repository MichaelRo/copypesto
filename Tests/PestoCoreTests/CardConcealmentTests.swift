// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("What a covered card still lets out")
struct CardConcealmentTests {
    @Test("an ordinary card offers everything")
    func ordinary() {
        let card = CardConcealment(screenShareBlur: false, sensitiveBlur: false)
        #expect(!card.isConcealed)
        #expect(card.allowsHoverDetail && card.allowsQuickLook && card.allowsAIActions && card.allowsDrag)
    }

    @Test("a card covered for screen sharing shows nothing of itself in a second window, a drag or an AI answer")
    func screenShare() {
        let card = CardConcealment(screenShareBlur: true, sensitiveBlur: false)
        #expect(card.isConcealed)
        #expect(!card.allowsHoverDetail && !card.allowsQuickLook && !card.allowsAIActions && !card.allowsDrag)
    }

    @Test("a sensitive card that has not been shown does the same until it is shown")
    func sensitive() {
        let card = CardConcealment(screenShareBlur: false, sensitiveBlur: true)
        #expect(card.isConcealed)
        #expect(!card.allowsHoverDetail && !card.allowsQuickLook && !card.allowsAIActions && !card.allowsDrag)
    }

    @Test("either cover is enough")
    func either() {
        #expect(CardConcealment(screenShareBlur: true, sensitiveBlur: true).isConcealed)
    }

    @Test("a masked secret that has not been shown hands out nothing, a drag included")
    func maskedSecretNotShown() {
        let card = CardConcealment(screenShareBlur: false, nsfwBlurred: false, maskedSecret: true, secretShown: false)

        #expect(card.isConcealed)
        #expect(!card.allowsHoverDetail && !card.allowsQuickLook && !card.allowsAIActions && !card.allowsDrag)
    }

    @Test("a masked secret that is being shown can be dragged, and is covered again when it hides")
    func maskedSecretShown() {
        let shown = CardConcealment(screenShareBlur: false, nsfwBlurred: false, maskedSecret: true, secretShown: true)
        let hidden = CardConcealment(screenShareBlur: false, nsfwBlurred: false, maskedSecret: true, secretShown: false)

        #expect(!shown.isConcealed)
        #expect(hidden.isConcealed)
    }

    @Test("a card with no secret is not covered by the secret rule")
    func noSecret() {
        let card = CardConcealment(screenShareBlur: false, nsfwBlurred: false, maskedSecret: false, secretShown: false)

        #expect(!card.isConcealed)
    }

    @Test("screen sharing still covers a shown secret")
    func screenShareOverridesAShownSecret() {
        let card = CardConcealment(screenShareBlur: true, nsfwBlurred: false, maskedSecret: true, secretShown: true)

        #expect(card.isConcealed)
    }

    @Test("a clip that has not been judged yet hands out nothing, so a picture cannot leak before it is checked")
    func pendingAnalysis() {
        let card = CardConcealment(
            screenShareBlur: false, nsfwBlurred: false, maskedSecret: false, secretShown: false, pendingAnalysis: true
        )

        #expect(card.isConcealed)
        #expect(!card.allowsHoverDetail && !card.allowsQuickLook && !card.allowsAIActions && !card.allowsDrag)
    }

    @Test("Decode is offered on a masked secret that has not been shown")
    func decodeOnMaskedSecret() {
        let card = CardConcealment(screenShareBlur: false, nsfwBlurred: false, maskedSecret: true, secretShown: false)
        #expect(card.allowsDecode)
    }

    @Test("Decode is not offered under a screen share or Hide Clip Contents, even when the secret is masked")
    func decodeNotUnderScreenShare() {
        let card = CardConcealment(screenShareBlur: true, nsfwBlurred: false, maskedSecret: true, secretShown: false)
        #expect(!card.allowsDecode)
    }

    @Test("Decode is not offered on a card covered by the content filter or a pending analysis")
    func decodeNotUnderOtherCovers() {
        #expect(!CardConcealment(screenShareBlur: false, nsfwBlurred: true, maskedSecret: true, secretShown: false)
            .allowsDecode)
        #expect(!CardConcealment(
            screenShareBlur: false, nsfwBlurred: false, maskedSecret: true, secretShown: false, pendingAnalysis: true
        ).allowsDecode)
    }

    @Test("the plain initializer never offers Decode")
    func decodeNotFromPlainInit() {
        #expect(!CardConcealment(screenShareBlur: false, sensitiveBlur: true).allowsDecode)
        #expect(!CardConcealment(screenShareBlur: false, sensitiveBlur: false).allowsDecode)
    }
}
