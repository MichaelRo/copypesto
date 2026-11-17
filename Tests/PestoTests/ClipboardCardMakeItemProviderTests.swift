// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import PestoCore
import Testing
import UniformTypeIdentifiers
@testable import Pesto

extension HostedGlobals {
    @Suite("ClipboardCard.makeItemProvider", .serialized)
    @MainActor
    final class ClipboardCardMakeItemProviderTests {
        private func makeEncryptedItem(
            type: ClipboardType,
            text: String,
            data: Data? = nil,
            mimeType: String = "public.utf8-plain-text",
            customTitle: String? = nil
        ) throws
        -> ClipboardItem {
            let payload = data ?? Data(text.utf8)
            let item = ClipboardItem(
                type: type,
                previewText: text,
                contentHash: UUID().uuidString,
                byteSize: payload.count,
                deviceID: "test",
                sequenceNumber: 1
            )
            item.customTitle = customTitle
            let aad = BlobEncryption.associatedData(itemID: item.id, field: .blob)
            let sealed = try BlobEncryption().encrypt(payload, associatedData: aad)
            let blob = ClipboardBlob(
                encryptedData: sealed.ciphertext,
                nonceData: sealed.nonce,
                mimeType: mimeType
            )
            blob.aadBound = true
            item.blob = blob
            return item
        }

        private func loadData(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    }
                }
            }
        }

        @Test("text clip registers text UTIs and loads UTF-8 text")
        func whenTextClip_thenRegistersTextUTIsAndLoadsText() async throws {
            let item = try makeEncryptedItem(type: .text, text: "hello drag", customTitle: "Greeting")
            let provider = ClipboardCard(item: item).makeItemProvider()

            for identifier in DragTypes.textIdentifiers {
                #expect(provider.hasItemConformingToTypeIdentifier(identifier))
            }
            let data = try await loadData(from: provider, typeIdentifier: UTType.utf8PlainText.identifier)
            #expect(String(data: data, encoding: .utf8) == "hello drag")
        }

        @Test("url clip registers public.url in addition to text UTIs")
        func whenURLClip_thenRegistersURL() {
            let item = ClipboardItem(
                type: .url,
                previewText: "https://copypesto.net",
                contentHash: UUID().uuidString,
                byteSize: 21,
                deviceID: "test",
                sequenceNumber: 1
            )
            let provider = ClipboardCard(item: item).makeItemProvider()
            #expect(provider.hasItemConformingToTypeIdentifier(UTType.url.identifier))
            #expect(provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier))
        }

        @Test("image clip registers PNG/TIFF UTIs and loads image bytes")
        func whenImageClip_thenRegistersImageUTIs() async throws {
            let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            let item = try makeEncryptedItem(
                type: .image,
                text: "Image",
                data: png,
                mimeType: UTType.png.identifier
            )
            let provider = ClipboardCard(item: item).makeItemProvider()

            for identifier in DragTypes.imageIdentifiers(storedUTI: UTType.png.identifier) {
                #expect(provider.hasItemConformingToTypeIdentifier(identifier))
            }
            let loaded = try await loadData(from: provider, typeIdentifier: UTType.png.identifier)
            #expect(loaded == png)
        }

        @Test("3-file clip registers NSFilenamesPboardType plist with all three paths")
        func whenThreeFileClip_thenRegistersFilenamesPlist() async throws {
            let urls = [
                URL(fileURLWithPath: "/tmp/one.txt"),
                URL(fileURLWithPath: "/tmp/two.png"),
                URL(fileURLWithPath: "/tmp/three.pdf")
            ]
            let encoded = FileClip.encode(urls)
            let item = ClipboardItem(
                type: .file,
                previewText: encoded,
                contentHash: UUID().uuidString,
                byteSize: encoded.utf8.count,
                deviceID: "test",
                sequenceNumber: 1
            )
            let provider = ClipboardCard(item: item).makeItemProvider()

            #expect(provider.hasItemConformingToTypeIdentifier(DragTypes.filenamesPboardType))
            let plistData = try await loadData(from: provider, typeIdentifier: DragTypes.filenamesPboardType)
            let paths = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String]
            #expect(paths == urls.map(\.path))
        }
    }
}
