// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import Pesto
@testable import PestoCore

@Suite("A copy from the shelf is a use of the clip")
struct ShelfCopyTests {
    @Test("copying moves the clip to the front but does not count as a paste, which Pesto did not make")
    @MainActor
    func copyIsRecorded() throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let item = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 1000), type: .text, previewText: "x",
            contentHash: "h", byteSize: 1, deviceID: "d", sequenceNumber: 1
        )
        context.insert(item)

        AppState().noteCopied(item, in: context)

        #expect(item.timestamp > Date(timeIntervalSince1970: 1000))
        #expect(item.pasteCount == 0)
    }
}
