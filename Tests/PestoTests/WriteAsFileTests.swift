// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Writing a clip as a file", .serialized)
    @MainActor
    struct WriteAsFileTests {
        private let container: ModelContainer
        private let service: StorageService
        private let state = AppState()

        init() async throws {
            container = try ModelContainerSetup.makeInMemory()
            service = StorageService(modelContainer: container)
        }

        private func ingestText(_ text: String) async throws -> ClipboardItem {
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text",
                payload: Data(text.utf8),
                payloadString: text,
                contentHash: UUID().uuidString
            ))
            return try #require(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first)
        }

        private func pasteboardFileURLs() -> [URL] {
            (AppPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        }

        @Test("a text clip is written to a private temporary .txt file named for the clip and put on the pasteboard")
        func whenTextClip_thenWritesTxtFileURLToPasteboard() async throws {
            let item = try await ingestText("hello world")
            item.customTitle = "Greeting"

            let payload = state.writeAsFile(item)
            let urls = pasteboardFileURLs()
            defer { urls.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }

            #expect(payload == .nonText)
            #expect(urls.count == 1)
            let fileURL = try #require(urls.first)
            #expect(fileURL.lastPathComponent == "Greeting.txt")
            #expect(fileURL.deletingLastPathComponent().lastPathComponent.hasPrefix(DragFile.folderPrefix))
            #expect(try String(contentsOf: fileURL, encoding: .utf8) == "hello world")
            let mode = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int
            #expect(mode == 0o600)
        }

        @Test("an untitled text clip uses the 'Pesto clip' name prefix")
        func whenUntitledTextClip_thenUsesPestoClipName() async throws {
            let item = try await ingestText("plain note")

            let payload = state.writeAsFile(item)
            let urls = pasteboardFileURLs()
            defer { urls.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }

            #expect(payload == .nonText)
            let fileURL = try #require(urls.first)
            #expect(fileURL.lastPathComponent.hasPrefix("Pesto clip "))
            #expect(fileURL.pathExtension == "txt")
            #expect(try String(contentsOf: fileURL, encoding: .utf8) == "plain note")
        }

        @Test("a color clip with no blob writes its preview text as a .txt file")
        func whenColorClipWithNoBlob_thenWritesPreviewText() throws {
            let item = ClipboardItem(
                type: .color,
                previewText: "#FF5500",
                contentHash: UUID().uuidString,
                byteSize: 7,
                deviceID: "d",
                sequenceNumber: 1
            )

            let payload = state.writeAsFile(item)
            let urls = pasteboardFileURLs()
            defer { urls.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }

            #expect(payload == .nonText)
            let fileURL = try #require(urls.first)
            #expect(fileURL.pathExtension == "txt")
            #expect(try String(contentsOf: fileURL, encoding: .utf8) == "#FF5500")
        }

        @Test("an image clip is written with the extension for its UTI")
        func whenImageClip_thenWritesImageBytesWithUTIExtension() throws {
            let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            let itemID = UUID()
            let aad = BlobEncryption.associatedData(itemID: itemID, field: .blob)
            let sealed = try BlobEncryption().encrypt(bytes, associatedData: aad)
            let blob = ClipboardBlob(encryptedData: sealed.ciphertext, nonceData: sealed.nonce, mimeType: "public.png")
            blob.aadBound = true
            let item = ClipboardItem(
                id: itemID,
                type: .image,
                previewText: "Image",
                contentHash: UUID().uuidString,
                byteSize: bytes.count,
                deviceID: "d",
                sequenceNumber: 2
            )
            item.blob = blob
            blob.item = item

            let payload = state.writeAsFile(item)
            let urls = pasteboardFileURLs()
            defer { urls.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }

            #expect(payload == .nonText)
            let fileURL = try #require(urls.first)
            #expect(fileURL.lastPathComponent.hasPrefix("Pesto picture "))
            #expect(fileURL.pathExtension == "png")
            #expect(try Data(contentsOf: fileURL) == bytes)
        }

        @Test("a locked history refuses writeAsFile and touches nothing on the pasteboard")
        func whenHistoryLocked_thenReturnsNilAndWritesNothing() async throws {
            let item = try await ingestText("should not leave")
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("before", forType: .string)
            AppDefaults.store.set(true, forKey: "biometricLockEnabled")
            defer { AppDefaults.store.removeObject(forKey: "biometricLockEnabled") }
            state.checkAndApplyBiometricLock()

            let payload = state.writeAsFile(item)

            #expect(payload == nil)
            #expect(AppPasteboard.general.string(forType: .string) == "before")
        }

        @Test("a secret clip cannot be written as a file")
        func whenSecretClip_thenReturnsNilAndWritesNothing() async throws {
            let secret = try await ingestText("4242 4242 4242 4242")
            #expect(secret.sensitivityRaw != nil)
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("before", forType: .string)

            let payload = state.writeAsFile(secret)

            #expect(payload == nil)
            #expect(AppPasteboard.general.string(forType: .string) == "before")
        }

        @Test("a file clip is refused by writeAsFile")
        func whenFileClip_thenReturnsNil() {
            let fileItem = ClipboardItem(
                type: .file,
                previewText: "/tmp/example.txt",
                contentHash: UUID().uuidString,
                byteSize: 16,
                deviceID: "d",
                sequenceNumber: 3
            )
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("before", forType: .string)

            let payload = state.writeAsFile(fileItem)

            #expect(payload == nil)
            #expect(AppPasteboard.general.string(forType: .string) == "before")
        }

        @Test("an unreadable blob fails closed and reports a user error")
        func whenBlobUnreadable_thenFailsClosedAndReportsError() {
            let brokenBlob = ClipboardBlob(
                encryptedData: Data([0x00, 0x01, 0x02]),
                nonceData: Data(repeating: 0x03, count: 12),
                mimeType: "public.png"
            )
            let brokenItem = ClipboardItem(
                type: .image,
                previewText: "Corrupted image",
                contentHash: UUID().uuidString,
                byteSize: 3,
                deviceID: "d",
                sequenceNumber: 4
            )
            brokenItem.blob = brokenBlob
            brokenBlob.item = brokenItem

            let payload = state.writeAsFile(brokenItem)

            #expect(payload == nil)
            #expect(state.lastUserError != nil)
        }

        @Test("a text blob that cannot be decoded fails closed instead of falling back to preview text")
        func whenTextBlobCannotDecodeAsText_thenFailsClosedAndReportsError() throws {
            let undecodableBytes = Data([0xFF, 0xFE])
            let itemID = UUID()
            let aad = BlobEncryption.associatedData(itemID: itemID, field: .blob)
            let sealed = try BlobEncryption().encrypt(undecodableBytes, associatedData: aad)
            let blob = ClipboardBlob(encryptedData: sealed.ciphertext, nonceData: sealed.nonce, mimeType: "public.data")
            blob.aadBound = true
            let item = ClipboardItem(
                id: itemID,
                type: .text,
                previewText: "fallback preview",
                contentHash: UUID().uuidString,
                byteSize: undecodableBytes.count,
                deviceID: "d",
                sequenceNumber: 5
            )
            item.blob = blob
            blob.item = item
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("before", forType: .string)

            let payload = state.writeAsFile(item)

            #expect(payload == nil)
            #expect(state.lastUserError != nil)
            #expect(AppPasteboard.general.string(forType: .string) == "before")
        }

        @Test("a non-color clip without a blob fails closed instead of writing preview text")
        func whenNonColorClipHasNoBlob_thenFailsClosedAndReportsError() {
            let item = ClipboardItem(
                type: .text,
                previewText: "preview only",
                contentHash: UUID().uuidString,
                byteSize: 12,
                deviceID: "d",
                sequenceNumber: 6
            )
            AppPasteboard.general.clearContents()
            AppPasteboard.general.setString("before", forType: .string)

            let payload = state.writeAsFile(item)

            #expect(payload == nil)
            #expect(state.lastUserError != nil)
            #expect(AppPasteboard.general.string(forType: .string) == "before")
        }
    }
}
