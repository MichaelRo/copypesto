// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Saving a clip's text from the Mac's Edit Text window", .serialized)
    @MainActor
    struct TextEditSaveTests {
        private let state = AppState()
        private let history = UndoHistory()
        private let container: ModelContainer
        private let service: StorageService

        init() throws {
            container = try ModelContainerSetup.makeInMemory()
            service = StorageService(modelContainer: container, environment: .testing { [history] in
                $0.undoHistory = history
            })
            state.storageService = service
        }

        private func ingest(_ text: String, at offset: TimeInterval = 0) async throws -> UUID {
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                timestamp: Date(timeIntervalSince1970: 1_800_000_000 + offset),
                contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            ))
            await service.waitForBackgroundWork()
            return try #require(clips().first { $0.blob?.decryptedText() == text }).id
        }

        private func clips() throws -> [ClipboardItem] {
            try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        }

        private func text(of id: UUID) throws -> String? {
            try clips().first { $0.id == id }?.blob?.decryptedText()
        }

        @Test("a save replaces the text, offers Undo, and ⌘Z restores the old text")
        func whenSaved_thenUndoOfferedAndUndoRestores() async throws {
            let id = try await ingest("draft one")

            let result = await state.saveEditedText(id: id, text: "draft two")

            #expect(result == .saved)
            #expect(try text(of: id) == "draft two")
            #expect(state.undoOffer == .editText)
            state.performUndo()
            var attempts = 0
            while try text(of: id) != "draft one", attempts < 200 {
                try await Task.sleep(for: .milliseconds(25))
                attempts += 1
            }
            #expect(try text(of: id) == "draft one")
        }

        @Test("a save and its undo each tell the shelf to draw the clip again once the new text has arrived")
        func whenSavedAndUndone_thenTheShelfIsToldToRedraw() async throws {
            let id = try await ingest("before the edit")
            let store = HistoryStore(container: container)
            store.refresh()
            state.historyStore = store

            #expect(await state.saveEditedText(id: id, text: "after the edit") == .saved)
            try await waitUntil { state.textEditGeneration == 1 }
            #expect(store.item(for: id)?.blob?.decryptedText() == "after the edit")

            state.performUndo()
            try await waitUntil { state.textEditGeneration == 2 }
            #expect(store.item(for: id)?.blob?.decryptedText() == "before the edit")
        }

        private func waitUntil(_ condition: () -> Bool) async throws {
            var attempts = 0
            while !condition(), attempts < 200 {
                try await Task.sleep(for: .milliseconds(25))
                attempts += 1
            }
            #expect(condition())
        }

        @Test("another clip's text is saved and both clips keep it")
        func whenTextBelongsToAnotherClip_thenSaved() async throws {
            let first = try await ingest("first clip", at: 0)
            let second = try await ingest("second clip", at: 10)

            let result = await state.saveEditedText(id: first, text: "second clip")

            #expect(result == .saved)
            #expect(try text(of: first) == "second clip")
            #expect(try text(of: second) == "second clip")
        }

        @Test("a blank text and a text over the size limit are refused with their own words")
        func whenBlankOrTooLarge_thenRefused() async throws {
            let id = try await ingest("keeps its words")

            #expect(await state.saveEditedText(id: id, text: "  \n") == .refused("A clip can\u{2019}t be empty."))
            let huge = String(repeating: "a", count: ClipSizePolicy.maxTextBytes + 1)
            let result = await state.saveEditedText(id: id, text: huge)
            guard case let .refused(words) = result else {
                Issue.record("a text over the limit was not refused: \(result)")
                return
            }
            #expect(!words.isEmpty)
            #expect(try text(of: id) == "keeps its words")
        }

        @Test("a locked history keeps the editor and its draft, refuses the save until the unlock, then saves")
        func whenLocked_thenTheEditorStaysAndSavesAfterTheUnlock() async throws {
            let id = try await ingest("locked words")
            var closed = 0
            state.closeTextEditor = { closed += 1 }
            AppDefaults.store.set(true, for: Setting.biometricLockEnabled)
            AppDefaults.store.set(false, for: Setting.uitestAuthenticationGranted)
            AuthenticationGrace.shared.clear()
            defer {
                AuthenticationGrace.shared.clear()
                AppDefaults.store.removeValue(for: Setting.biometricLockEnabled)
                AppDefaults.store.removeValue(for: Setting.uitestAuthenticationGranted)
            }

            let refused = await state.saveEditedText(id: id, text: "changed while locked")

            #expect(refused == .refused(TextEditPolicy.lockedMessage))
            #expect(closed == 0, "the draft stays in its window")
            #expect(try text(of: id) == "locked words")

            AppDefaults.store.set(true, for: Setting.uitestAuthenticationGranted)
            let saved = await state.saveEditedText(id: id, text: "changed while locked")

            #expect(saved == .saved)
            #expect(closed == 0)
            #expect(try text(of: id) == "changed while locked")
        }

        @Test("editing a revealed secret re-seals and re-classifies the saved text")
        func whenSecretEdited_thenResealedAndReclassified() async throws {
            let secret = "sk-ant-api03-EXAMPLEEXAMPLEEXAMPLEEXAMPLE1234567890abcdef"
            let id = try await ingest(secret)
            let initial = try #require(clips().first { $0.id == id })
            #expect(initial.sensitivity == .oauthToken)
            #expect(initial.sensitivityMaskedPreview != nil)

            let toPlain = await state.saveEditedText(id: id, text: "ordinary reminder note")
            #expect(toPlain == .saved)
            let afterPlain = try #require(clips().first { $0.id == id })
            #expect(afterPlain.sensitivity == nil)
            #expect(afterPlain.sensitivityMaskedPreview == nil)
            #expect(try text(of: id) == "ordinary reminder note")

            let replacementSecret = "sk-ant-api03-NEWSECRET1234567890abcdef1234567890"
            let toSecret = await state.saveEditedText(id: id, text: replacementSecret)
            #expect(toSecret == .saved)
            let afterSecret = try #require(clips().first { $0.id == id })
            #expect(afterSecret.sensitivity == .oauthToken)
            #expect(afterSecret.sensitivityMaskedPreview != nil)
            #expect(try text(of: id) == replacementSecret)
        }
    }
}
