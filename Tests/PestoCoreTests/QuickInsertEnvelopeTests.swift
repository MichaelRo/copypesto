// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Testing
@testable import PestoCore

@Suite("The quick-insert set is sealed so only the app and its AutoFill extension open it")
struct QuickInsertEnvelopeTests {
    private let secretLooking = "dinner at eight, the gate code is 4417"

    private let ids = [UUID(), UUID()]

    private func sampleSet() -> QuickInsertSet {
        QuickInsertSet(createdAt: Date(timeIntervalSince1970: 1_800_000_000), entries: [
            QuickInsertEntry(
                id: ids[0], section: .pinned, kind: .text, title: "Home address", text: "12 Basil Lane",
                expandsOnInsert: false
            ),
            QuickInsertEntry(
                id: ids[1], section: .recent, kind: .text, title: secretLooking, text: secretLooking,
                expandsOnInsert: false
            )
        ])
    }

    private func temporaryFile() throws -> QuickInsertFile {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-quick-insert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return QuickInsertFile(root: root)
    }

    @Test("a sealed set opens with its key and holds what was sealed")
    func whenOpenedWithItsKey_thenTheSetComesBack() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try QuickInsertEnvelope.seal(sampleSet(), with: key)

        #expect(try QuickInsertEnvelope.open(sealed, with: key) == sampleSet())
    }

    @Test("no clip's text, and no title, is readable in the sealed bytes")
    func whenSealed_thenNoPlaintextIsInTheBytes() throws {
        let sealed = try QuickInsertEnvelope.seal(sampleSet(), with: SymmetricKey(size: .bits256))

        for needle in ["12 Basil Lane", "Home address", "gate code", "pinned", "recent"] {
            #expect(sealed.range(of: Data(needle.utf8)) == nil, "\(needle) is readable")
        }
    }

    @Test("another key does not open it")
    func whenOpenedWithAnotherKey_thenItIsRefused() throws {
        let sealed = try QuickInsertEnvelope.seal(sampleSet(), with: SymmetricKey(size: .bits256))

        #expect(throws: QuickInsertError.wrongKey) {
            try QuickInsertEnvelope.open(sealed, with: SymmetricKey(size: .bits256))
        }
    }

    @Test("a truncated file, a changed version or a changed purpose does not open")
    func whenTheBytesChange_thenItIsRefused() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try QuickInsertEnvelope.seal(sampleSet(), with: key)

        #expect(throws: QuickInsertError.self) {
            try QuickInsertEnvelope.open(sealed.prefix(sealed.count - 5), with: key)
        }
        #expect(throws: QuickInsertError.damaged) { try QuickInsertEnvelope.open(sealed.prefix(6), with: key) }
        var otherVersion = Data(sealed)
        otherVersion[8] = 2
        #expect(throws: QuickInsertError.damaged) { try QuickInsertEnvelope.open(otherVersion, with: key) }
        var otherPurpose = Data(sealed)
        otherPurpose[0] = UInt8(ascii: "X")
        #expect(throws: QuickInsertError.damaged) { try QuickInsertEnvelope.open(otherPurpose, with: key) }
    }

    @Test("an inbox file, sealed for the app's other purpose, is not a quick-insert set")
    func whenGivenAnotherPurposesBytes_thenItIsRefused() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try QuickInsertEnvelope.seal(sampleSet(), with: key)
        var relabelled = Data("PESTOINB".utf8)
        relabelled.append(sealed.dropFirst(8))

        #expect(throws: QuickInsertError.damaged) { try QuickInsertEnvelope.open(relabelled, with: key) }
    }

    @Test("the file is written whole and read back; an empty set is a file too, and removing it leaves none")
    func whenWrittenAndRemoved_thenTheFileFollows() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.root) }
        let key = SymmetricKey(size: .bits256)

        #expect(throws: QuickInsertError.missing) { try file.read(with: key) }
        try file.write(sampleSet(), with: key)
        #expect(try file.read(with: key) == sampleSet())
        try file.write(.empty, with: key)
        #expect(try file.read(with: key).entries.isEmpty)
        file.remove()
        #expect(!file.exists)
    }

    @Test("a file larger than any set could be is refused without being read whole")
    func whenTheFileIsTooLarge_thenItIsRefused() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.root) }
        try Data(count: QuickInsertPolicy.maxFileBytes + 1).write(to: file.url)

        #expect(throws: QuickInsertError.tooLarge) { try file.read(with: SymmetricKey(size: .bits256)) }
    }

    @Test("the key is made once, stored under the quick-insert account, and removed on request")
    func whenTheKeyIsLoaded_thenItIsStoredOnce() throws {
        let secrets = MemorySecrets()
        let keys = QuickInsertKeyStore(secrets: secrets)

        #expect(try keys.key() == nil)
        let made = try keys.loadOrCreate()
        #expect(try keys.loadOrCreate() == made)
        #expect(try secrets
            .read(service: AppIdentity.keychainService, account: AppIdentity.quickInsertKeyAccount) != nil)
        #expect(try secrets.read(service: AppIdentity.keychainService, account: AppIdentity.blobKeyAccount) == nil)
        keys.remove()
        #expect(try keys.key() == nil)
    }
}
