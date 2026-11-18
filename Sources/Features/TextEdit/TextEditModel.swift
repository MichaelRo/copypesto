// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore

/// What the Edit Text window holds for one clip: the text it opened with, the draft, and the last refusal.
@MainActor
@Observable
final class TextEditModel {
    private(set) var clipID: UUID
    private(set) var original: String
    private(set) var isMonospaced: Bool
    var draft: String
    private(set) var message: String?
    private(set) var isSaving = false
    @ObservationIgnored private let save: (UUID, String) async -> TextEditSaveResult
    @ObservationIgnored var onClose: (() -> Void)?

    init(
        clipID: UUID, text: String, isMonospaced: Bool, save: @escaping (UUID, String) async -> TextEditSaveResult
    ) {
        self.clipID = clipID
        original = text
        self.isMonospaced = isMonospaced
        draft = text
        self.save = save
    }

    var hasUnsavedChanges: Bool {
        draft != original
    }

    var canSave: Bool {
        !isSaving && TextEditPolicy.canSave(original: original, draft: draft)
    }

    /// Gives the window another clip; only while nothing is typed, so a draft is never thrown away.
    func load(clipID: UUID, text: String, isMonospaced: Bool) {
        guard !hasUnsavedChanges else { return }
        self.clipID = clipID
        original = text
        self.isMonospaced = isMonospaced
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
