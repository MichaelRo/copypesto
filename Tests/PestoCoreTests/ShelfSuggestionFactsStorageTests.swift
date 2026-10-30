// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Shelf suggestion facts storage fetching")
struct ShelfSuggestionFactsStorageTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
    }

    private func service() async -> StorageService {
        StorageService(modelContainer: container)
    }

    @Test("when facts gathered, returns at most twenty rows plus shortcut holders without decrypted content")
    func whenFactsGathered_thenBoundedAndNoText() async throws {
        let service = await service()
        let context = ModelContext(container)

        // Insert 30 clips with pasteCount >= 3
        for i in 0..<30 {
            let item = ClipboardItem(
                type: .text,
                previewText: "preview-\(i)",
                contentHash: "hash-\(i)",
                byteSize: 10,
                deviceID: "dev",
                sequenceNumber: Int64(i)
            )
            item.pasteCount = i + 3
            context.insert(item)
        }

        // Insert 1 clip with shortcut but pasteCount = 0
        let shortcutHolder = ClipboardItem(
            type: .text,
            previewText: "shortcut-holder",
            contentHash: "hash-sh",
            byteSize: 10,
            deviceID: "dev",
            sequenceNumber: 100,
            isPinned: true
        )
        shortcutHolder.pinnedHotkeyIndex = 5
        context.insert(shortcutHolder)

        // Insert 1 sensitive clip
        let sensitive = ClipboardItem(
            type: .text,
            previewText: "secret",
            sensitivity: .password,
            contentHash: "hash-sec",
            byteSize: 10,
            deviceID: "dev",
            sequenceNumber: 101
        )
        sensitive.pasteCount = 100
        context.insert(sensitive)

        try context.save()

        let facts = try await service.shelfSuggestionFacts(unavailableSlots: [1, 2])
        #expect(facts.clips.count <= 21) // 20 frequent + 1 shortcut holder
        #expect(facts.clips.contains { $0.id == shortcutHolder.id })
        #expect(!facts.clips.contains { $0.id == sensitive.id }) // Sensitive omitted at query level
        #expect(facts.assignedSlots.contains(5))
        #expect(facts.unavailableSlots == [1, 2])
    }

    @Test("when asked which clip ids still exist, deleted ones are left out")
    func whenIdsChecked_thenOnlyExistingReturned() async throws {
        let service = await service()
        let context = ModelContext(container)
        let kept = ClipboardItem(
            type: .text, previewText: "kept", contentHash: "hash-kept", byteSize: 4, deviceID: "dev", sequenceNumber: 1
        )
        context.insert(kept)
        try context.save()

        let found = try await service.existingClipIDs(among: [kept.id, UUID()])
        #expect(found == [kept.id])
    }
}
