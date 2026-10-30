// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("The Undo banner and ⌘Z in the app", .serialized)
    @MainActor
    struct UndoOfferTests {
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

        private func clipCount() throws -> Int {
            try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).count
        }

        private func ingestAndDelete(_ text: String) async throws {
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                timestamp: .now, contentHash: "hash-\(text)"
            ))
            let ids = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).map(\.id)
            try await service.deleteItems(ids: ids, reason: .user)
        }

        private func waitUntil(_ condition: () throws -> Bool) async throws {
            var attempts = 0
            while try !condition(), attempts < 200 {
                try await Task.sleep(for: .milliseconds(25))
                attempts += 1
            }
        }

        @Test("a delete that was kept offers Undo, and one that was not offers nothing")
        func whenDeleted_thenTheBannerOffersUndo() async throws {
            state.offerUndo(since: history.recordedCount)
            #expect(state.undoOffer == nil)

            let mark = history.recordedCount
            try await ingestAndDelete("a")
            state.offerUndo(since: mark)

            #expect(state.undoOffer == .deleteClips(1))
            state.dismissUndoOffer()
            #expect(state.undoOffer == nil)
        }

        @Test("⌘Z brings the clip back, takes the banner down and lets the shelf filter again")
        func whenUndone_thenTheClipIsBackAndTheBannerGone() async throws {
            let mark = history.recordedCount
            try await ingestAndDelete("a")
            state.offerUndo(since: mark)
            #expect(try clipCount() == 0)
            let generation = state.undoGeneration

            state.performUndo()
            try await waitUntil { try clipCount() == 1 }

            #expect(try clipCount() == 1)
            #expect(state.undoOffer == nil)
            #expect(state.undoGeneration == generation + 1)
            #expect(history.redoLabel == .deleteClips(1))
        }

        @Test("⇧⌘Z deletes it again, and ⌘Z with nothing to undo does nothing")
        func whenRedone_thenDeletedAgain() async throws {
            try await ingestAndDelete("a")
            state.performUndo()
            try await waitUntil { try clipCount() == 1 }

            state.performRedo()
            try await waitUntil { try clipCount() == 0 }
            #expect(try clipCount() == 0)

            history.clear()
            let generation = state.undoGeneration
            state.performUndo()
            try await Task.sleep(for: .milliseconds(100))
            #expect(state.undoGeneration == generation)
        }

        @Test("a deleted collection is offered back and comes back")
        func whenACollectionIsDeleted_thenUndoRestoresIt() async throws {
            let context = ModelContext(container)
            let board = Pinboard(name: "Work", symbolName: "briefcase", colorHex: "#112233", sortOrder: 0)
            context.insert(board)
            try context.save()

            state.deleteCollection(id: board.id, fromShelf: true)
            try await waitUntil { state.undoOffer != nil }
            #expect(state.undoOffer == .deleteCollection("Work"))

            state.performUndo()
            try await waitUntil { try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).count == 1 }
            #expect(try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).count == 1)
        }
    }
}
