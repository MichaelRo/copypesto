// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import Pesto
@testable import PestoCore

/// Quick Look left decrypted previews in $TMPDIR.
@Suite("Quick Look cleanup")
struct PrivacyCleanupTests {
    @Test("the sweep removes leftover Quick Look folders and nothing else")
    func sweep_removesOnlyPestoQuickLookFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-sweep-test-\(UUID().uuidString)", isDirectory: true)
        let stale = root.appendingPathComponent("pesto-ql-\(UUID().uuidString)", isDirectory: true)
        let other = root.appendingPathComponent("someone-elses-folder", isDirectory: true)
        for directory in [stale, other] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: directory.appendingPathComponent("file.txt"))
        }
        defer { try? FileManager.default.removeItem(at: root) }

        QuickLookPreviewController.sweepStaleTempFiles(in: root)

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @MainActor
    @Test("closing the Quick Look panel removes the decrypted file, which is private while it exists")
    func quickLook_removesItsFileWhenThePanelCloses() throws {
        let item = ClipboardItem(
            type: .text, previewText: "an account number", contentHash: "h", byteSize: 17,
            deviceID: "d", sequenceNumber: 1
        )
        let controller = QuickLookPreviewController()

        let file = try #require(controller.prepareFile(for: item))
        let folder = file.deletingLastPathComponent()
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let folderAttributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #expect((folderAttributes[.posixPermissions] as? Int) == 0o700)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @MainActor
    @Test("closing it from the app, as when the history locks or the shelf hides, removes the decrypted file too")
    func quickLook_removesItsFileWhenTheAppClosesIt() throws {
        let item = ClipboardItem(
            type: .text, previewText: "an account number", contentHash: "h", byteSize: 17,
            deviceID: "d", sequenceNumber: 1
        )
        let controller = QuickLookPreviewController()
        let folder = try #require(controller.prepareFile(for: item)).deletingLastPathComponent()

        controller.close()

        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @MainActor
    @Test("Quick Look tracks its open state and notifies when state changes or closes")
    func quickLook_tracksOpenStateAndFiresCallbacks() {
        let item = ClipboardItem(
            type: .text, previewText: "some preview text", contentHash: "h", byteSize: 17,
            deviceID: "d", sequenceNumber: 1
        )
        let controller = QuickLookPreviewController()
        var stateHistory: [Bool] = []
        var closeFired = false
        controller.onStateChanged = { stateHistory.append($0) }
        controller.onClose = { closeFired = true }

        #expect(!controller.isOpen)
        controller.show(item: item)
        #expect(controller.isOpen)
        #expect(stateHistory == [true])

        controller.close()
        #expect(!controller.isOpen)
        #expect(stateHistory == [true, false])
        #expect(closeFired)
    }

    @MainActor
    @Test("Quick Look toggle closes when already open")
    func quickLook_toggleClosesWhenAlreadyOpen() {
        let item = ClipboardItem(
            type: .text, previewText: "some preview text", contentHash: "h", byteSize: 17,
            deviceID: "d", sequenceNumber: 1
        )
        let controller = QuickLookPreviewController()
        controller.show(item: item)
        #expect(controller.isOpen)

        controller.toggle(item: item)
        #expect(!controller.isOpen)
    }

    @MainActor
    @Test("Quick Look previews existing file clips directly and leaves disk files untouched on close")
    func quickLook_fileClipUsesExistingDiskURLsWithoutDeletingThem() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleFile = tempDir.appendingPathComponent("test-video.mp4")
        try "video-bytes".write(to: sampleFile, atomically: true, encoding: .utf8)

        let item = ClipboardItem(
            type: .file, previewText: sampleFile.absoluteString, contentHash: "fh", byteSize: 11,
            deviceID: "d", sequenceNumber: 1
        )
        let controller = QuickLookPreviewController()
        let previewURL = try #require(controller.prepareFile(for: item))
        #expect(previewURL == sampleFile)
        #expect(controller.numberOfPreviewItems(in: nil) == 1)

        controller.close()
        #expect(FileManager.default.fileExists(atPath: sampleFile.path))
    }
}
