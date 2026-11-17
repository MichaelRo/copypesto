// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("DeletedFilePaste", .serialized)
    @MainActor
    final class DeletedFilePasteTests {
        @Test("pasting a file clip whose files were deleted returns nil and shows the filesGone toast")
        func whenFilesDeleted_thenWriteItemReturnsNilAndShowsFilesGoneToast() {
            let missingPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-deleted-\(UUID().uuidString).txt")
            let item = ClipboardItem(
                type: .file,
                previewText: FileClip.encode([missingPath]),
                contentHash: UUID().uuidString,
                byteSize: missingPath.path.utf8.count,
                deviceID: "test",
                sequenceNumber: 1
            )

            let state = AppState()
            var shownToasts: [StatusToast] = []
            state.showToast = { shownToasts.append($0) }

            let result = state.writeItem(item)
            #expect(result == nil)
            #expect(shownToasts == [.filesGone])
        }

        @Test("pasting a file clip with at least one existing file succeeds")
        func whenOneFileExists_thenWriteItemSucceeds() throws {
            let existing = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-present-\(UUID().uuidString).txt")
            try Data("ok".utf8).write(to: existing)
            defer { try? FileManager.default.removeItem(at: existing) }

            let missing = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-missing-\(UUID().uuidString).txt")

            let item = ClipboardItem(
                type: .file,
                previewText: FileClip.encode([missing, existing]),
                contentHash: UUID().uuidString,
                byteSize: 32,
                deviceID: "test",
                sequenceNumber: 1
            )

            let state = AppState()
            var shownToasts: [StatusToast] = []
            state.showToast = { shownToasts.append($0) }

            let result = state.writeItem(item)
            #expect(result != nil)
            #expect(shownToasts.isEmpty)
        }
    }
}
