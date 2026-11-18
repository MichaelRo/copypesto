// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@Suite("The widget snapshot is sealed so only the app and its widget open it")
struct WidgetSnapshotSealingTests {
    private let id = UUID()
    private let otherID = UUID()

    private func snapshot() -> WidgetSnapshot {
        WidgetSnapshot(createdAt: Date(timeIntervalSince1970: 1_800_000_000), theme: .brand, clips: [
            WidgetClip(
                id: id, kind: .url, text: "https://copypesto.net/guide", linkHost: "copypesto.net",
                linkPath: "/guide", source: "Safari", date: Date(timeIntervalSince1970: 1_799_999_000),
                isPinned: true
            ),
            WidgetClip(
                id: otherID, kind: .text, text: "dinner at eight, the gate code is 4417", source: "Notes",
                date: Date(timeIntervalSince1970: 1_799_998_000), thumbnail: Data("JFIFthumb".utf8)
            )
        ])
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-widget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("a sealed snapshot opens with its key and holds what was sealed")
    func whenOpenedWithItsKey_thenTheSnapshotComesBack() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try SealedFileEnvelope.seal(snapshot(), as: .widgetSnapshot, with: key)

        #expect(try SealedFileEnvelope.open(WidgetSnapshot.self, from: sealed, as: .widgetSnapshot, with: key)
            == snapshot())
        #expect(sealed.prefix(8) == Data("PESTOWGT".utf8))
    }

    @Test("no clip's text, host, source or thumbnail is readable in the file's bytes")
    func whenWritten_thenNoPlaintextIsInTheFile() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = SealedGroupFile(root: root, format: .widgetSnapshot)
        try file.write(snapshot(), with: SymmetricKey(size: .bits256))
        let bytes = try Data(contentsOf: file.url)

        for needle in ["copypesto", "/guide", "gate code", "Safari", "Notes", "JFIF", id.uuidString, "isPinned"] {
            #expect(bytes.range(of: Data(needle.utf8)) == nil, "\(needle) is readable")
        }
    }

    @Test("another key, a truncated file, another version or another purpose does not open")
    func whenTheKeyOrTheBytesDiffer_thenItIsRefused() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try SealedFileEnvelope.seal(snapshot(), as: .widgetSnapshot, with: key)
        func open(_ data: Data, _ key: SymmetricKey) throws -> WidgetSnapshot {
            try SealedFileEnvelope.open(WidgetSnapshot.self, from: data, as: .widgetSnapshot, with: key)
        }

        #expect(throws: SealedFileError.wrongKey) { try open(sealed, SymmetricKey(size: .bits256)) }
        #expect(throws: SealedFileError.self) { try open(sealed.prefix(sealed.count - 1), key) }
        #expect(throws: SealedFileError.damaged) { try open(sealed.prefix(9), key) }
        var otherVersion = Data(sealed)
        otherVersion[8] = 2
        #expect(throws: SealedFileError.damaged) { try open(otherVersion, key) }
        let otherPurpose = SealedFileFormat(
            fileName: AppIdentity.widgetSnapshotFileName, magic: "PESTOWGT", version: 1,
            purpose: "pesto.quick-insert.v1", maxFileBytes: WidgetSnapshotPolicy.maxFileBytes
        )
        #expect(throws: SealedFileError.wrongKey) {
            try SealedFileEnvelope.open(WidgetSnapshot.self, from: sealed, as: otherPurpose, with: key)
        }
    }

    @Test("the widget key does not open the quick-insert file, and the quick-insert key does not open the widget's")
    func whenTheOtherFilesKeyIsUsed_thenNeitherOpens() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let secrets = MemorySecrets()
        let widgetKey = try SharedFileKeyStore(secrets: secrets, account: AppIdentity.widgetKeyAccount).loadOrCreate()
        let quickKey = try QuickInsertKeyStore(secrets: secrets).loadOrCreate()
        #expect(widgetKey != quickKey)
        let widgetFile = SealedGroupFile(root: root, format: .widgetSnapshot)
        let quickFile = QuickInsertFile(root: root)
        try widgetFile.write(snapshot(), with: widgetKey)
        try quickFile.write(.empty, with: quickKey)
        #expect(widgetFile.url != quickFile.url)

        #expect(throws: SealedFileError.wrongKey) { try quickFile.read(with: widgetKey) }
        #expect(throws: SealedFileError.wrongKey) { try widgetFile.read(WidgetSnapshot.self, with: quickKey) }
        let quickBytes = try Data(contentsOf: quickFile.url)
        #expect(throws: SealedFileError.damaged) {
            try SealedFileEnvelope.open(WidgetSnapshot.self, from: quickBytes, as: .widgetSnapshot, with: quickKey)
        }
        #expect(try widgetFile.read(WidgetSnapshot.self, with: widgetKey) == snapshot())
    }

    @Test("a file larger than any snapshot could be is refused without being read whole, and remove leaves none")
    func whenTheFileIsTooLarge_thenItIsRefused() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = SealedGroupFile(root: root, format: .widgetSnapshot)
        let key = SymmetricKey(size: .bits256)
        #expect(throws: SealedFileError.missing) { try file.read(WidgetSnapshot.self, with: key) }
        try Data(count: WidgetSnapshotPolicy.maxFileBytes + 1).write(to: file.url)

        #expect(throws: SealedFileError.tooLarge) { try file.read(WidgetSnapshot.self, with: key) }
        file.remove()
        #expect(!file.exists)
    }

    @Test("the widget key lives under its own account, never the history key's or the quick-insert key's")
    func whenTheKeyIsMade_thenItHasItsOwnAccount() throws {
        let secrets = MemorySecrets()
        let keys = SharedFileKeyStore(secrets: secrets, account: AppIdentity.widgetKeyAccount)

        let made = try keys.loadOrCreate()
        #expect(try keys.loadOrCreate() == made)
        for other in [AppIdentity.blobKeyAccount, AppIdentity.quickInsertKeyAccount, AppIdentity.inboxKeyAccount] {
            #expect(try secrets.read(service: AppIdentity.keychainService, account: other) == nil)
        }
        keys.remove()
        #expect(try keys.key() == nil)
    }
}
