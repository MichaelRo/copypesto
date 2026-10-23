// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

@Suite("Quick menu")
struct QuickMenuTests {
    private func insert(_ count: Int, hiddenNewest: Bool, into context: ModelContext) {
        for index in 0..<count {
            let isNewest = index == count - 1
            let item = ClipboardItem(
                timestamp: Date(timeIntervalSince1970: Double(1000 + index)), type: .text,
                previewText: "clip \(index)", contentHash: UUID().uuidString, byteSize: 4, deviceID: "d",
                sequenceNumber: Int64(index)
            )
            item.isNSFW = hiddenNewest && isNewest
            context.insert(item)
        }
    }

    @Test("it fetches five clips, newest first, not the whole history")
    func fetchesFive() throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let context = ModelContext(container)
        insert(40, hiddenNewest: false, into: context)
        try context.save()

        let shown = try context.fetch(QuickMenuView.descriptor(hidesSensitive: false))

        #expect(shown.count == 5)
        #expect(shown.first?.previewText == "clip 39")
    }

    @Test("a sensitive clip the shelf hides is not the newest card in the quick menu")
    func hiddenClipIsNotOffered() throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let context = ModelContext(container)
        insert(8, hiddenNewest: true, into: context)
        try context.save()

        let shown = try context.fetch(QuickMenuView.descriptor(hidesSensitive: true))

        #expect(shown.count == 5)
        #expect(shown.allSatisfy { !$0.isNSFW })
        #expect(shown.first?.previewText == "clip 6")
    }

    @Test("a paste counts and moves the clip to the front, in the quick menu as on the shelf")
    @MainActor
    func pasteIsRecorded() throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let context = ModelContext(container)
        let item = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 1000), type: .text, previewText: "x",
            contentHash: "h", byteSize: 1, deviceID: "d", sequenceNumber: 1
        )
        context.insert(item)

        AppState().notePasted(item, in: context)

        #expect(item.pasteCount == 1)
        #expect(item.timestamp > Date(timeIntervalSince1970: 1000))
    }

    @Test("with no storage service a background paste note is still written, so a first run loses nothing")
    @MainActor
    func backgroundPasteNote_fallsBackToTheMainContext() throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let context = ModelContext(container)
        let item = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 1000), type: .text, previewText: "x",
            contentHash: "h", byteSize: 1, deviceID: "d", sequenceNumber: 1
        )
        context.insert(item)

        AppState().notePastedInBackground(item, in: context)

        #expect(item.pasteCount == 1)
    }
}
