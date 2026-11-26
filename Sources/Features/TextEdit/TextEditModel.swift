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
    /// The snippet being made from this clip (ADR 0075); nil while the window edits the plain text.
    private(set) var snippetDraft: SnippetEditorDraft?
    @ObservationIgnored private let save: (UUID, String) async -> TextEditSaveResult
    @ObservationIgnored private let saveSnippet: (UUID, String, String) async -> TextEditSaveResult
    @ObservationIgnored var onClose: (() -> Void)?

    init(
        clipID: UUID, text: String, isMonospaced: Bool, isEditable: Bool = true,
        saveSnippet: @escaping (UUID, String, String) async -> TextEditSaveResult = { _, _, _ in
            .refused(TextEditPolicy.failedMessage)
        },
        save: @escaping (UUID, String) async -> TextEditSaveResult
    ) {
        self.clipID = clipID
        original = text
        self.isMonospaced = isMonospaced
        self.isEditable = isEditable
        draft = text
        self.saveSnippet = saveSnippet
        self.save = save
    }

    var hasUnsavedChanges: Bool {
        draft != original || snippetDraft != nil
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
        snippetDraft = nil
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

    /// Turns the window to the snippet editor, seeded with the text as it is typed now, so an unsaved edit is kept.
    func beginSnippet(title: String) {
        guard isEditable, !isSaving else { return }
        snippetDraft = SnippetEditorDraft(clipID: clipID, title: title, text: draft)
        message = nil
    }

    /// Back to the plain text, as it was typed before the snippet editor opened.
    func endSnippet() {
        snippetDraft = nil
        message = nil
    }

    func commitSnippet(_ snippet: SnippetEditorDraft) async {
        guard snippetDraft != nil, !isSaving else { return }
        snippetDraft = snippet
        isSaving = true
        message = nil
        let result = await saveSnippet(clipID, snippet.title, snippet.text)
        isSaving = false
        if case let .refused(words) = result {
            message = words
            return
        }
        onClose?()
    }

    /// Closes the window whatever it shows (the cover's Close): a covered window drops its draft, as before.
    func close() {
        onClose?()
    }

    /// Esc and Cancel: out of the snippet editor first, then the window.
    func cancel() {
        if snippetDraft != nil {
            endSnippet()
            return
        }
        onClose?()
    }
}
