// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Who may open Edit Text on the Mac, when Save is ready, and what a refusal says")
struct TextEditPolicyTests {
    private let open = CardConcealment(
        screenShareBlur: false,
        nsfwBlurred: false,
        maskedSecret: false,
        secretShown: false
    )

    private func offered(
        _ type: ClipboardType,
        pending: Bool = false,
        hasBlob: Bool = true,
        bytes: Int = 40,
        concealment: CardConcealment? = nil
    )
    -> Bool {
        TextEditPolicy.isOffered(
            type: type, analysisPending: pending, hasBlob: hasBlob, byteSize: bytes, concealment: concealment ?? open
        )
    }

    @Test("text, code, a link and a color are offered; a picture and a file are not")
    func whenKindsDiffer_thenOnlyTextLikeClipsAreOffered() {
        #expect(offered(.text))
        #expect(offered(.code))
        #expect(offered(.url))
        #expect(offered(.color))
        #expect(!offered(.image))
        #expect(!offered(.file))
    }

    @Test("a clip still being judged, or one with no stored text, is not offered")
    func whenPendingOrBlobless_thenNotOffered() {
        #expect(!offered(.text, pending: true))
        #expect(!offered(.text, hasBlob: false))
    }

    @Test("a text up to the editor's ceiling is offered and one past it is not")
    func whenTextIsLarge_thenTheCeilingDecides() {
        #expect(offered(.text, bytes: TextEditPolicy.maxEditableBytes))
        #expect(!offered(.text, bytes: TextEditPolicy.maxEditableBytes + 1))
    }

    @Test("a masked secret is offered only while it is shown")
    func whenSecretIsMasked_thenOnlyShowOpensTheEditor() {
        let masked = CardConcealment(screenShareBlur: false, nsfwBlurred: false, maskedSecret: true, secretShown: false)
        let shown = CardConcealment(screenShareBlur: false, nsfwBlurred: false, maskedSecret: true, secretShown: true)
        #expect(!offered(.text, concealment: masked))
        #expect(offered(.text, concealment: shown))
    }

    @Test("a card covered for a screen share or by the content filter offers nothing")
    func whenCovered_thenNotOffered() {
        let shared = CardConcealment(screenShareBlur: true, nsfwBlurred: false, maskedSecret: true, secretShown: true)
        let blurred = CardConcealment(
            screenShareBlur: false,
            nsfwBlurred: true,
            maskedSecret: false,
            secretShown: false
        )
        #expect(!offered(.text, concealment: shared))
        #expect(!offered(.url, concealment: blurred))
        #expect(!CardMenuItem.editText.isOffered(covered: true))
    }

    @Test("Save is ready only for a changed text that is not blank")
    func whenDraftChanges_thenSaveFollowsIt() {
        #expect(!TextEditPolicy.canSave(original: "same", draft: "same"))
        #expect(!TextEditPolicy.canSave(original: "same", draft: " \n\t"))
        #expect(!TextEditPolicy.canSave(original: "same", draft: ""))
        #expect(TextEditPolicy.canSave(original: "same", draft: "same."))
    }

    @Test("each refusal is said in plain words; a save and an unchanged text close the editor")
    func whenOutcomeArrives_thenTheResultSaysWhatHappened() {
        #expect(TextEditPolicy.result(for: .saved) == .saved)
        #expect(TextEditPolicy.result(for: .unchanged) == .unchanged)
        #expect(TextEditPolicy.result(for: .empty) == .refused("A clip can\u{2019}t be empty."))
        #expect(TextEditPolicy.result(for: .missing) == .refused("This clip can\u{2019}t be edited."))
        #expect(TextEditPolicy.result(for: .notText) == .refused("This clip can\u{2019}t be edited."))
        #expect(TextEditSaveResult.saved.closesEditor)
        #expect(TextEditSaveResult.unchanged.closesEditor)
        #expect(!TextEditSaveResult.refused("x").closesEditor)
    }

    @Test("a locked history and a failed save have their own words")
    func whenLockedOrFailed_thenTheMessageSaysWhatToDo() {
        #expect(TextEditPolicy.lockedMessage == "Your history is locked. Unlock it, then save again.")
        #expect(TextEditPolicy.failedMessage == "Couldn\u{2019}t save the change.")
    }
}
