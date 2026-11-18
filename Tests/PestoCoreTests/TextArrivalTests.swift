// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("A card is drawn again once every edited clip holds its new text", .serialized)
@MainActor
struct TextArrivalTests {
    private let first = UUID()
    private let second = UUID()

    @Test("one clip that moved is not enough while another edited clip still shows its old text")
    func whenOnlySomeClipsChanged_thenTheTextHasNotArrived() {
        let old = [first: "a", second: "b"]
        #expect(!TextArrival.hasArrived(old) { $0 == first ? "a2" : "b" })
        #expect(TextArrival.hasArrived(old) { $0 == first ? "a2" : "b2" })
    }

    @Test("a clip that is gone (deleted, or its model left its context) counts as arrived and is never read")
    func whenAClipIsGone_thenItCountsAsArrived() {
        #expect(TextArrival.hasArrived([first: "a"]) { _ in nil })
        #expect(TextArrival.hasArrived([:]) { _ in "anything" })
    }

    @Test("the next Undo and Redo of a text edit name the clips they change, and nothing else does")
    func whenATextEditIsUndoable_thenItsClipsAreNamed() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let history = UndoHistory()
        let service = StorageService(modelContainer: container, environment: .testing { $0.undoHistory = history })
        let payload = Data("before the edit".utf8)
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: payload, payloadString: "before the edit",
            contentHash: Data(SHA256.hash(data: payload)).hexString
        ))
        let id = try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first?.id)
        #expect(history.undoReplacedClipIDs.isEmpty)

        try await service.updateText(id: id, text: "after the edit")
        #expect(history.undoReplacedClipIDs == [id])
        #expect(history.redoReplacedClipIDs.isEmpty)

        try await service.undo()
        #expect(history.redoReplacedClipIDs == [id])

        try await service.deleteItems(ids: [id], reason: .user)
        #expect(history.undoReplacedClipIDs.isEmpty, "a delete replaces no text")
    }
}
