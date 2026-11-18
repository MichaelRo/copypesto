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

        @Test("another clip's text is refused in plain words and nothing changes")
        func whenTextBelongsToAnotherClip_thenRefused() async throws {
            let first = try await ingest("first clip", at: 0)
            _ = try await ingest("second clip", at: 10)

            let result = await state.saveEditedText(id: first, text: "second clip")

            #expect(result == .refused("Another clip already has this text."))
            #expect(try text(of: first) == "first clip")
            #expect(state.undoOffer == nil)
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

        @Test("a locked history refuses the save, closes the editor and keeps the old text")
        func whenLocked_thenRefusedAndEditorClosed() async throws {
            let id = try await ingest("locked words")
            var closed = 0
            state.closeTextEditor = { closed += 1 }
            AppDefaults.store.set(true, for: Setting.biometricLockEnabled)
            defer { AppDefaults.store.removeObject(forKey: Setting.biometricLockEnabled.name) }

            let result = await state.saveEditedText(id: id, text: "changed while locked")

            #expect(result == .refused(TextEditPolicy.lockedMessage))
            #expect(closed > 0)
            #expect(try text(of: id) == "locked words")
        }
    }
}
