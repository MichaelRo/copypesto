// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@Suite("Recognized text store")
struct RecognizedTextStoreTests {
    private func makeStore(key: SymmetricKey = SymmetricKey(size: .bits256)) -> (RecognizedTextStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-ocr-\(UUID().uuidString)", isDirectory: true)
        return (RecognizedTextStore(directory: directory, key: { key }), directory)
    }

    @Test("a text round-trips, with accents and line breaks")
    func whenSaved_thenLoads() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let text = "Résumé\nQuarterly 数字 summary\n" + String(repeating: "word ", count: 400)

        try store.save(text, for: id)

        #expect(store.load(for: id) == text)
        #expect(store.exists(for: id))
    }

    @Test("nothing saved means nothing loaded")
    func whenNeverSaved_thenNil() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        #expect(store.load(for: id) == nil)
        #expect(!store.exists(for: id))
    }

    @Test("the file on disk is ciphertext and readable only by its owner")
    func whenSaved_thenEncryptedAndPrivate() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(String(repeating: "A", count: 4096), for: UUID())

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
            .appendingPathComponent("pesto-ocr-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        try RecognizedTextStore(directory: directory, key: { SymmetricKey(size: .bits256) }).save(
            "secret words",
            for: id
        )

        #expect(RecognizedTextStore(directory: directory, key: { SymmetricKey(size: .bits256) }).load(for: id) == nil)
    }

    @Test("a file moved to another clip's name does not open")
    func whenMovedToAnotherClip_thenNil() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (first, second) = (UUID(), UUID())
        try store.save("text of the first clip", for: first)
        let sealed = try #require(store.sealedFile(for: first))

        try store.restoreSealedFile(sealed, for: second)

        #expect(store.load(for: second) == nil)
        #expect(store.load(for: first) == "text of the first clip")
    }

    @Test("a sealed file can be kept and put back, as Undo does")
    func whenRestoredFromSealedFile_thenLoads() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        try store.save("kept for undo", for: id)
        let sealed = try #require(store.sealedFile(for: id))
        store.delete(ids: [id])
        #expect(store.load(for: id) == nil)

        try store.restoreSealedFile(sealed, for: id)

        #expect(store.load(for: id) == "kept for undo")
    }

    @Test("delete removes only the named texts; deleteAll removes everything")
    func whenDeleted_thenGone() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (first, second, third) = (UUID(), UUID(), UUID())
        for id in [first, second, third] {
            try store.save("text", for: id)
        }

        store.delete(ids: [first, second])
        #expect(!store.exists(for: first))
        #expect(!store.exists(for: second))
        #expect(store.exists(for: third))

        store.deleteAll()
        #expect(!store.exists(for: third))
    }
}
