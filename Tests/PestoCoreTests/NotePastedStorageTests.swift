// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("A paste of something made from a clip counts as using that clip")
struct NotePastedStorageTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
    }

    private func item(_ id: UUID) throws -> ClipboardItem? {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id }
    }

    @Test("noting a paste moves the clip to the front of the history and counts it")
    func whenNotedPasted_thenNewestAndCounted() async throws {
        let service = StorageService(modelContainer: container)
        let older = try #require(await service.addSnippet("older {{x}}"))
        let newer = try #require(await service.addSnippet("newer {{y}}"))
        let before = try #require(try item(newer)).timestamp

        let found = try await service.notePasted(id: older, at: before.addingTimeInterval(60))

        let bumped = try #require(try item(older))
        #expect(found)
        #expect(bumped.pasteCount == 1)
        #expect(bumped.timestamp > before)
    }

    @Test("a clip that is not there is reported, and nothing else changes")
    func whenUnknownID_thenFalse() async throws {
        let service = StorageService(modelContainer: container)
        let kept = try #require(await service.addSnippet("kept {{z}}"))

        let found = try await service.notePasted(id: UUID(), at: .now)

        #expect(!found)
        #expect(try #require(try item(kept)).pasteCount == 0)
    }
}
