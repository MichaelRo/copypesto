// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Copy Recognized Text is an ordinary copy, so the text becomes a clip of its own", .serialized)
    @MainActor
    final class CopyRecognizedTextTests {
        private let state = AppState()
        private let container: ModelContainer
        private let store: RecognizedTextStore

        init() throws {
            AppPasteboard.general.clearContents()
            container = try ModelContainerSetup.makeInMemory()
            store = RecognizedTextStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("pesto-copy-ocr-\(UUID().uuidString)", isDirectory: true)
            )
        }

        private func picture(reading text: String) -> ClipboardItem {
            let item = ClipboardItem(
                type: .image, sourceAppName: "Preview", previewText: text, contentHash: UUID().uuidString,
                byteSize: 1000, deviceID: "test-device", sequenceNumber: 1
            )
            item.timestamp = Date(timeIntervalSince1970: 1_700_000_000)
            ModelContext(container).insert(item)
            return item
        }

        private var boardTypes: [String] {
            (AppPasteboard.general.types ?? []).map(\.rawValue)
        }

        @Test("the text is on the board, unprotected, and the write is not one the watcher skips")
        func whenCopied_thenTextIsOnTheBoardAndNotOwnWrite() {
            let item = picture(reading: "Boarding pass gate B22")

            let copied = state.copyRecognizedText(of: item, store: store)

            #expect(copied)
            #expect(AppPasteboard.general.string(forType: .string) == "Boarding pass gate B22")
            #expect(!PasteboardProtection.isProtected(types: boardTypes))
            #expect(!state.ownWrites.isOwn(changeCount: AppPasteboard.general.changeCount))
        }

        @Test("the picture is not moved: copying its text is not a use of the picture")
        func whenCopied_thenThePictureKeepsItsPlace() {
            let item = picture(reading: "Boarding pass gate B22")
            let before = item.timestamp

            _ = state.copyRecognizedText(of: item, store: store)

            #expect(item.timestamp == before)
        }

        @Test("a picture with no text writes nothing and says so")
        func whenThereIsNoText_thenNothingIsWritten() {
            let item = picture(reading: "")
            AppPasteboard.general.setString("kept", forType: .string)

            let copied = state.copyRecognizedText(of: item, store: store)

            #expect(!copied)
            #expect(AppPasteboard.general.string(forType: .string) == "kept")
        }
    }
}
