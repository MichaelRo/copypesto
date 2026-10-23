// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@Suite("Link preview image store")
struct LinkPreviewImageStoreTests {
    private func makeStore(key: SymmetricKey = SymmetricKey(size: .bits256)) -> (LinkPreviewImageStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-og-\(UUID().uuidString)", isDirectory: true)
        return (LinkPreviewImageStore(directory: directory, key: { key }), directory)
    }

    @Test("an image round-trips")
    func whenSaved_thenLoads() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let image = Data((0..<2048).map { UInt8($0 % 251) })

        try store.save(image, for: id)

        #expect(store.load(for: id) == image)
    }

    @Test("nothing saved means nothing loaded")
    func whenNeverSaved_thenNil() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.load(for: UUID()) == nil)
    }

    @Test("the file on disk is ciphertext and readable only by its owner")
    func whenSaved_thenEncryptedAndPrivate() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let image = Data(repeating: 0x41, count: 4096)
        try store.save(image, for: id)

        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first)
        let onDisk = try Data(contentsOf: file)
        #expect(onDisk.range(of: Data(repeating: 0x41, count: 64)) == nil, "plaintext found on disk")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test("a different key cannot read it")
    func whenKeyChanges_thenNil() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-og-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        try LinkPreviewImageStore(directory: directory, key: { SymmetricKey(size: .bits256) })
            .save(Data(repeating: 1, count: 100), for: id)

        #expect(LinkPreviewImageStore(directory: directory, key: { SymmetricKey(size: .bits256) }).load(for: id) == nil)
    }

    @Test("delete removes only the named images; deleteAll removes everything")
    func whenDeleted_thenGone() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (first, second, third) = (UUID(), UUID(), UUID())
        for id in [first, second, third] {
            try store.save(Data([1, 2, 3]), for: id)
        }

        store.delete(ids: [first, second])
        #expect(store.load(for: first) == nil)
        #expect(store.load(for: second) == nil)
        #expect(store.load(for: third) != nil)

        store.deleteAll()
        #expect(store.load(for: third) == nil)
    }
}
