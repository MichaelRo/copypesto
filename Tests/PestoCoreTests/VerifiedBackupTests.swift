// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Verifying a backup file without reading it into memory")
struct VerifiedBackupTests {
    private let key = BackupKey.generate()
    private let passphrase = "correct horse battery staple"
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-verified-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func records() -> [BackupRecord] {
        [
            BackupRecord(kind: .item, metadata: Data("{\"id\":1}".utf8), payload: Data("hello".utf8)),
            BackupRecord(kind: .tombstone, metadata: Data("{\"id\":3}".utf8)),
            BackupRecord(kind: .item, metadata: Data("{\"id\":2}".utf8), payload: Data(repeating: 0xAB, count: 3000)),
            BackupRecord(kind: .collection, metadata: Data("{\"name\":\"Work\"}".utf8))
        ]
    }

    private func data(_ records: [BackupRecord]? = nil, sequence: UInt64 = 7) throws -> Data {
        try BackupFile.write(
            records: records ?? self.records(),
            origin: BackupOrigin(sequence: sequence, deviceID: "mac-1", createdAt: createdAt),
            key: key, passphrase: passphrase, iterations: 1000
        )
    }

    private func store(_ data: Data, as name: String = "backup.pestobackup") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func items(of backup: VerifiedBackup) async throws -> [BackupRecord] {
        var found: [BackupRecord] = []
        try await backup.forEachItem { found.append($0) }
        return found
    }

    private func errorFromVerify(_ data: Data) throws -> (any Error)? {
        let url = try store(data, as: "damaged-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try BackupFile.verify(url: url, credential: .passphrase(passphrase))
            return nil
        } catch {
            return error
        }
    }

    private func errorFromRead(_ data: Data) -> (any Error)? {
        do {
            _ = try BackupFile.read(data, credential: .passphrase(passphrase))
            return nil
        } catch {
            return error
        }
    }

    // MARK: Reading

    @Test("it reports the manifest and the counts, and hands back only the small records")
    func whenVerified_thenCountsAndSmallRecords() throws {
        let backup = try BackupFile.verify(url: store(data()), credential: .passphrase(passphrase))

        #expect(backup.manifest.recordCount == 4)
        #expect(backup.manifest.sequence == 7)
        #expect(backup.manifest.deviceID == "mac-1")
        #expect(backup.itemCount == 2 && backup.collectionCount == 1 && backup.deletionCount == 1)
        #expect(backup.smallRecords == [records()[1], records()[3]])
    }

    @Test("the clips are read back from the file one by one, in the order they were written")
    func whenEnumerated_thenEveryItemInOrder() async throws {
        let backup = try BackupFile.verify(url: store(data()), credential: .recoveryKey(key))

        let found = try await items(of: backup)

        #expect(found == [records()[0], records()[2]])
    }

    @Test("an empty backup has nothing to enumerate")
    func whenEmpty_thenNoItems() async throws {
        let backup = try BackupFile.verify(url: store(data([])), credential: .passphrase(passphrase))

        #expect(backup.manifest.recordCount == 0)
        #expect(try await items(of: backup).isEmpty)
    }

    @Test("an error in the body stops the enumeration and reaches the caller")
    func whenBodyThrows_thenEnumerationStops() async throws {
        struct Stop: Error {}
        let backup = try BackupFile.verify(url: store(data()), credential: .passphrase(passphrase))
        var seen = 0

        await #expect(throws: Stop.self) {
            try await backup.forEachItem { _ in
                seen += 1
                throw Stop()
            }
        }
        #expect(seen == 1)
    }

    // MARK: Refusals

    @Test("the wrong passphrase, the wrong recovery key and a file that is not a backup are refused")
    func whenCredentialOrFileIsWrong_thenRefused() throws {
        let url = try store(data())

        #expect(throws: BackupError.wrongCredential) {
            try BackupFile.verify(url: url, credential: .passphrase("not it"))
        }
        #expect(throws: BackupError.wrongCredential) {
            try BackupFile.verify(url: url, credential: .recoveryKey(BackupKey.generate()))
        }
        #expect(throws: BackupError.notABackup) {
            try BackupFile.verify(
                url: store(Data("just some text".utf8), as: "text.txt"),
                credential: .recoveryKey(key)
            )
        }
        #expect(throws: (any Error).self) {
            try BackupFile.verify(url: directory.appendingPathComponent("missing"), credential: .recoveryKey(key))
        }
    }

    @Test("flipping any single byte is refused, with the same error as reading the file whole")
    func whenAnyByteFlips_thenRefusedLikeRead() throws {
        let original = try data([
            BackupRecord(kind: .item, metadata: Data("m".utf8), payload: Data("payload".utf8)),
            BackupRecord(kind: .tombstone, metadata: Data("t".utf8))
        ])
        for position in 0..<original.count {
            var damaged = original
            damaged[position] ^= 0x01
            let streamed = try #require(try errorFromVerify(damaged), "byte \(position) went unnoticed")
            #expect(streamed as? BackupError == errorFromRead(damaged) as? BackupError, "byte \(position)")
        }
    }

    @Test("truncating at any length is refused, with the same error as reading the file whole")
    func whenTruncated_thenRefusedLikeRead() throws {
        let original = try data()
        for length in 0..<original.count {
            let damaged = original.prefix(length)
            let streamed = try #require(try errorFromVerify(Data(damaged)), "length \(length) was accepted")
            #expect(streamed as? BackupError == errorFromRead(Data(damaged)) as? BackupError, "length \(length)")
        }
    }

    @Test("appended bytes are refused")
    func whenExtended_thenRefused() throws {
        #expect(try errorFromVerify(data() + Data([0, 0, 0, 0])) != nil)
    }

    @Test("a swapped pair of chunks is refused")
    func whenChunksSwapped_thenRefused() throws {
        let original = try data()
        var offset = BackupFile.firstChunkOffset(in: original)
        var ranges: [Range<Int>] = []
        while offset < original.count {
            let length = (0..<4).reduce(0) { $0 << 8 | Int(original[offset + $1]) }
            ranges.append(offset..<offset + 4 + length)
            offset += 4 + length
        }
        var swapped = Data(original.prefix(BackupFile.firstChunkOffset(in: original)))
        swapped.append(original[ranges[1]])
        swapped.append(original[ranges[0]])
        for range in ranges.dropFirst(2) {
            swapped.append(original[range])
        }

        #expect(try errorFromVerify(swapped) != nil)
    }

    // MARK: The file under the reader

    @Test("a later backup that replaces the file does not change what this one restores")
    func whenFileIsReplaced_thenTheVerifiedContentIsStillRead() async throws {
        let url = try store(data())
        let backup = try BackupFile.verify(url: url, credential: .passphrase(passphrase))

        let replacement = directory.appendingPathComponent("next.partial")
        try data([BackupRecord(kind: .item, metadata: Data("other".utf8), payload: Data("x".utf8))], sequence: 8)
            .write(to: replacement)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)

        #expect(try await items(of: backup) == [records()[0], records()[2]])
    }

    @Test("a file deleted after verification can still be restored from")
    func whenFileIsDeleted_thenTheVerifiedContentIsStillRead() async throws {
        let url = try store(data())
        let backup = try BackupFile.verify(url: url, credential: .passphrase(passphrase))

        try FileManager.default.removeItem(at: url)

        #expect(try await items(of: backup).count == 2)
    }

    @Test("a chunk changed in place between the two passes is caught by the second")
    func whenFileChangesInPlace_thenSecondPassFails() async throws {
        let url = try store(data())
        let backup = try BackupFile.verify(url: url, credential: .passphrase(passphrase))

        let handle = try FileHandle(forUpdating: url)
        try handle.seek(toOffset: UInt64(BackupFile.headerLength + BackupFile.fileIDBlockLength + 4 + 12 + 2))
        let byte = try #require(try handle.read(upToCount: 1))
        try handle.seek(toOffset: UInt64(BackupFile.headerLength + BackupFile.fileIDBlockLength + 4 + 12 + 2))
        try handle.write(contentsOf: Data([byte[0] ^ 0xFF]))
        try handle.close()

        await #expect(throws: BackupError.corrupted) { try await backup.forEachItem { _ in } }
    }

    @Test("a settings record is carried whole, counted in the manifest and handed back for the app to read")
    func whenSettingsAreCarried_thenTheyComeBack() throws {
        let json = Data(#"{"version":1,"settings":{"appTheme":"mortar"}}"#.utf8)
        let withSettings = [BackupRecord.settings(json)] + records()
        let url = try store(data(withSettings))

        let verified = try BackupFile.verify(url: url, credential: .passphrase(passphrase))

        #expect(verified.settingsData == json)
        #expect(verified.manifest.recordCount == withSettings.count)
        #expect(verified.itemCount == 2)
        #expect(verified.collectionCount == 1)
    }

    @Test("a file with no settings record, such as one written before settings were carried, has none")
    func whenNoSettings_thenNil() throws {
        let url = try store(data())

        let verified = try BackupFile.verify(url: url, credential: .passphrase(passphrase))

        #expect(verified.settingsData == nil)
    }

    @Test("the whole-file reader gives the settings record back too, and restoring ignores it")
    func whenReadWhole_thenSettingsAreAmongTheRecords() throws {
        let json = Data(#"{"settings":{}}"#.utf8)
        let file = try data([BackupRecord.settings(json)] + records())

        let contents = try BackupFile.read(file, credential: .passphrase(passphrase))

        #expect(contents.records.first == BackupRecord.settings(json))
        #expect(contents.records.count(where: { $0.kind == .settings }) == 1)
    }
}
