// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore

/// What the Clip window (the Clip Inspector, ADR 0071) holds for one clip: the text it opened with, the draft, and the
/// last refusal. `isEditable` is false for a clip whose content is not text the person may edit (a picture, a file, a
/// hidden secret); the window then shows the content as the hover card does and edits only the details.
@MainActor
@Observable
final class TextEditModel {
    private(set) var clipID: UUID
    private(set) var original: String
    private(set) var isMonospaced: Bool
    private(set) var isEditable: Bool
    var draft: String
    private(set) var message: String?
    private(set) var isSaving = false
    @ObservationIgnored private let save: (UUID, String) async -> TextEditSaveResult
    @ObservationIgnored var onClose: (() -> Void)?

    init(
        clipID: UUID, text: String, isMonospaced: Bool, isEditable: Bool = true,
        save: @escaping (UUID, String) async -> TextEditSaveResult
    ) {
        self.clipID = clipID
        original = text
        self.isMonospaced = isMonospaced
        self.isEditable = isEditable
        draft = text
        self.save = save
    }

    var hasUnsavedChanges: Bool {
        draft != original
    }

    var canSave: Bool {
        isEditable && !isSaving && TextEditPolicy.canSave(original: original, draft: draft)
    }

    /// Puts the text back as it was opened.
    func revert() {
        draft = original
        message = nil
    }

    /// Gives the window another clip; only while nothing is typed, so a draft is never thrown away.
    func load(clipID: UUID, text: String, isMonospaced: Bool, isEditable: Bool = true) {
        guard !hasUnsavedChanges else { return }
        self.clipID = clipID
        original = text
        self.isMonospaced = isMonospaced
        self.isEditable = isEditable
        draft = text
        message = nil
    }

    func commit() async {
        guard canSave else { return }
        isSaving = true
        message = nil
        let result = await save(clipID, draft)
        isSaving = false
        if case let .refused(words) = result {
            message = words
            return
        }
        onClose?()
    }

    func cancel() {
        onClose?()
    }
}
