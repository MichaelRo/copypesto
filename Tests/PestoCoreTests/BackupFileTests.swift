// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Backup file")
struct BackupFileTests {
    private let key = BackupKey.generate()
    private let passphrase = "correct horse battery staple"
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func records() -> [BackupRecord] {
        [
            BackupRecord(kind: .item, metadata: Data("{\"id\":1}".utf8), payload: Data("hello".utf8)),
            BackupRecord(kind: .item, metadata: Data("{\"id\":2}".utf8), payload: Data(repeating: 0xAB, count: 3000)),
            BackupRecord(kind: .collection, metadata: Data("{\"name\":\"Work\"}".utf8)),
            BackupRecord(kind: .tombstone, metadata: Data("{\"id\":3}".utf8))
        ]
    }

    private func file(records: [BackupRecord]? = nil, sequence: UInt64 = 7) throws -> Data {
        try BackupFile.write(
            records: records ?? self.records(),
            origin: BackupOrigin(sequence: sequence, deviceID: "mac-1", createdAt: createdAt),
            key: key, passphrase: passphrase, iterations: 1000
        )
    }

    // MARK: Reusing a header

    @Test("a later backup written under an earlier header opens with the same passphrase and the recovery key")
    func whenHeaderReused_thenOpensWithEitherCredential() throws {
        let first = try file()
        let header = try #require(BackupFile.header(of: first))

        let later = try BackupFile.write(
            records: records(), origin: BackupOrigin(sequence: 8, deviceID: "mac-1", createdAt: createdAt),
            key: key, header: header
        )

        #expect(BackupFile.header(of: later) == header)
        #expect(try BackupFile.read(later, credential: .passphrase(passphrase)).records == records())
        #expect(try BackupFile.read(later, credential: .recoveryKey(key)).manifest.sequence == 8)
    }

    @Test("a header made for another key is refused, and so is anything that is not a header")
    func whenHeaderIsForAnotherKey_thenRefused() throws {
        let header = try #require(BackupFile.header(of: file()))
        let origin = BackupOrigin(sequence: 1, deviceID: "mac-1", createdAt: createdAt)

        #expect(throws: BackupError.wrongCredential) {
            try BackupFile.write(records: records(), origin: origin, key: BackupKey.generate(), header: header)
        }
        #expect(throws: BackupError.notABackup) {
            try BackupFile.write(records: records(), origin: origin, key: key, header: Data("nope".utf8))
        }
        #expect(BackupFile.header(of: Data("not a backup at all, only text".utf8)) == nil)
    }

    // MARK: Round trips

    @Test("a backup opens with its passphrase")
    func whenPassphrase_thenRoundTrips() throws {
        let contents = try BackupFile.read(file(), credential: .passphrase(passphrase))
        #expect(contents.records == records())
        #expect(contents.manifest == BackupManifest(
            recordCount: 4,
            sequence: 7,
            deviceID: "mac-1",
            createdAt: createdAt
        ))
    }

    @Test("a backup opens with the recovery key")
    func whenRecoveryKey_thenRoundTrips() throws {
        let recovered = try BackupKey(recoveryKey: key.recoveryKey)
        #expect(try BackupFile.read(file(), credential: .recoveryKey(recovered)).records == records())
    }

    @Test("an empty backup is valid")
    func whenNoRecords_thenRoundTrips() throws {
        let contents = try BackupFile.read(file(records: []), credential: .passphrase(passphrase))
        #expect(contents.records.isEmpty && contents.manifest.recordCount == 0)
    }

    @Test("plaintext never appears in the file")
    func whenWritten_thenNoPlaintext() throws {
        let secret = Data("the quick brown fox 4111 1111 1111 1111".utf8)
        let data = try file(records: [BackupRecord(kind: .item, metadata: Data("meta".utf8), payload: secret)])
        #expect(data.range(of: secret) == nil && data.range(of: Data("meta".utf8)) == nil)
    }

    @Test("two backups of the same content differ (fresh salt and nonces)")
    func whenWrittenTwice_thenDifferentBytes() throws {
        #expect(try file() != file())
    }

    // MARK: Wrong credentials

    @Test("the wrong passphrase is rejected as a wrong credential")
    func whenWrongPassphrase_thenWrongCredential() throws {
        let data = try file()
        #expect(throws: BackupError.wrongCredential) { try BackupFile.read(data, credential: .passphrase("nope")) }
    }

    @Test("the wrong recovery key is rejected as a wrong credential")
    func whenWrongRecoveryKey_thenWrongCredential() throws {
        let data = try file()
        #expect(throws: BackupError.wrongCredential) {
            try BackupFile.read(data, credential: .recoveryKey(BackupKey.generate()))
        }
    }

    // MARK: Tampering

    @Test("flipping any single byte anywhere is detected")
    func whenAnyByteFlips_thenRejected() throws {
        let original = try file(records: [
            BackupRecord(kind: .item, metadata: Data("m".utf8), payload: Data("payload".utf8)),
            BackupRecord(kind: .tombstone, metadata: Data("t".utf8))
        ])
        for position in 0..<original.count {
            var damaged = original
            damaged[position] ^= 0x01
            #expect(throws: BackupError.self, "byte \(position) went unnoticed") {
                try BackupFile.read(damaged, credential: .passphrase(passphrase))
            }
        }
    }

    @Test("truncating at any length is detected")
    func whenTruncated_thenRejected() throws {
        let original = try file()
        for length in 0..<original.count {
            #expect(throws: BackupError.self, "length \(length) was accepted") {
                try BackupFile.read(original.prefix(length), credential: .passphrase(passphrase))
            }
        }
    }

    @Test("appended bytes are detected")
    func whenExtended_thenRejected() throws {
        let data = try file() + Data([0, 0, 0, 0])
        #expect(throws: BackupError.self) { try BackupFile.read(data, credential: .passphrase(passphrase)) }
    }

    @Test("swapping two record chunks is detected")
    func whenChunksReordered_thenRejected() throws {
        let data = try file(records: [
            BackupRecord(kind: .item, metadata: Data("a".utf8), payload: Data("1111".utf8)),
            BackupRecord(kind: .item, metadata: Data("b".utf8), payload: Data("2222".utf8))
        ])
        let (first, second) = try chunkRanges(of: data)
        var swapped = Data(data.prefix(BackupFile.firstChunkOffset(in: data)))
        swapped += data[second]
        swapped += data[first]
        swapped += data[manifestRange(of: data)]
        #expect(throws: BackupError.corrupted) { try BackupFile.read(swapped, credential: .passphrase(passphrase)) }
    }

    @Test("dropping a record chunk is detected")
    func whenChunkDropped_thenRejected() throws {
        let data = try file()
        let (first, _) = try chunkRanges(of: data)
        var shorter = data
        shorter.removeSubrange(first)
        #expect(throws: BackupError.corrupted) { try BackupFile.read(shorter, credential: .passphrase(passphrase)) }
    }

    @Test("a chunk from another backup cannot be spliced in")
    func whenChunkSplicedFromAnotherFile_thenRejected() throws {
        let ours = try file()
        let theirs = try file()
        let (first, _) = try chunkRanges(of: ours)
        let (foreign, _) = try chunkRanges(of: theirs)
        var spliced = ours
        spliced.replaceSubrange(first, with: theirs[foreign])
        #expect(throws: BackupError.corrupted) { try BackupFile.read(spliced, credential: .passphrase(passphrase)) }
    }

    @Test("a chunk of an earlier backup written under the same header cannot be spliced into a later one")
    func whenChunkSplicedFromAnotherFileOfTheSameMac_thenRejected() throws {
        let header = try #require(BackupFile.header(of: file()))
        func backup(_ marker: String) throws -> Data {
            try BackupFile.write(
                records: [
                    BackupRecord(kind: .item, metadata: Data("a".utf8), payload: Data("\(marker)1".utf8)),
                    BackupRecord(kind: .item, metadata: Data("b".utf8), payload: Data("\(marker)2".utf8))
                ],
                origin: BackupOrigin(sequence: 1, deviceID: "mac-1", createdAt: createdAt), key: key, header: header
            )
        }
        let older = try backup("old")
        let newer = try backup("new")
        let (olderFirst, _) = try chunkRanges(of: older)
        let (newerFirst, _) = try chunkRanges(of: newer)
        var spliced = newer
        spliced.replaceSubrange(newerFirst, with: older[olderFirst])

        #expect(throws: BackupError.corrupted) { try BackupFile.read(spliced, credential: .passphrase(passphrase)) }
        #expect(try BackupFile.read(newer, credential: .passphrase(passphrase)).records.count == 2)
    }

    @Test("a file written before file ids existed still opens, with both credentials")
    func whenFileHasNoFileID_thenItStillOpens() throws {
        let header = try #require(BackupFile.header(of: file()))
        let legacy = try BackupFile.body(
            records: records(), origin: BackupOrigin(sequence: 3, deviceID: "mac-1", createdAt: createdAt),
            key: key, header: header, fileID: nil
        )

        #expect(BackupFile.firstChunkOffset(in: legacy) == BackupFile.headerLength)
        #expect(try BackupFile.read(legacy, credential: .passphrase(passphrase)).records == records())
        #expect(try BackupFile.read(legacy, credential: .recoveryKey(key)).manifest.sequence == 3)
    }

    @Test("a file id cannot be removed to make a file pass as an older one")
    func whenTheFileIDIsStripped_thenRejected() throws {
        let data = try file()
        var stripped = Data(data.prefix(BackupFile.headerLength))
        stripped += data.dropFirst(BackupFile.headerLength + BackupFile.fileIDBlockLength)

        #expect(throws: BackupError.corrupted) { try BackupFile.read(stripped, credential: .passphrase(passphrase)) }
    }

    @Test("every backup carries its own file id")
    func whenTwoBackupsAreWritten_thenTheirIDsDiffer() throws {
        let header = try #require(BackupFile.header(of: file()))
        let origin = BackupOrigin(sequence: 1, deviceID: "mac-1", createdAt: createdAt)
        let first = try BackupFile.write(records: records(), origin: origin, key: key, header: header)
        let second = try BackupFile.write(records: records(), origin: origin, key: key, header: header)
        let range = BackupFile.headerLength..<BackupFile.headerLength + BackupFile.fileIDBlockLength

        #expect(first[range] != second[range])
        #expect(first[range].prefix(8) == BackupFile.fileIDMarker)
    }

    // MARK: Format

    @Test("something that is not a backup is not one")
    func whenNotABackup_thenNotABackup() {
        #expect(throws: BackupError.notABackup) { try BackupFile.read(Data("hello".utf8), credential: .passphrase("x"))
        }
        #expect(throws: BackupError.notABackup) { try BackupFile.read(Data(), credential: .passphrase("x")) }
    }

    @Test("a newer format version is refused by number, not misread")
    func whenNewerVersion_thenUnsupported() throws {
        var data = try file()
        data[9] = 2
        #expect(throws: BackupError.unsupportedVersion(2)) { try BackupFile.read(
            data,
            credential: .passphrase(passphrase)
        ) }
    }

    @Test("an absurd iteration count is refused instead of hanging")
    func whenIterationsAbsurd_thenCorrupted() throws {
        var data = try file()
        data.replaceSubrange(11..<15, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: BackupError.corrupted) { try BackupFile.read(data, credential: .passphrase(passphrase)) }
    }

    // MARK: Helpers

    private func chunkRanges(of data: Data) throws -> (Range<Int>, Range<Int>) {
        var offset = BackupFile.firstChunkOffset(in: data)
        var ranges: [Range<Int>] = []
        while offset < data.count {
            let length = (0..<4).reduce(0) { $0 << 8 | Int(data[offset + $1]) }
            ranges.append(offset..<offset + 4 + length)
            offset += 4 + length
        }
        return (ranges[0], ranges[1])
    }

    private func manifestRange(of data: Data) -> Range<Int> {
        var offset = BackupFile.firstChunkOffset(in: data)
        var last = offset..<offset
        while offset < data.count {
            let length = (0..<4).reduce(0) { $0 << 8 | Int(data[offset + $1]) }
            last = offset..<offset + 4 + length
            offset += 4 + length
        }
        return last
    }

    @Test("a header can be checked against a key without opening the file")
    func headerBelongsToItsKeyOnly() throws {
        let header = try BackupFile.makeHeader(key: key, passphrase: "one", iterations: 1000)
        let rewrapped = try BackupFile.makeHeader(key: key, passphrase: "two", iterations: 1000)
        let other = try BackupFile.makeHeader(key: BackupKey.generate(), passphrase: "one", iterations: 1000)

        #expect(BackupFile.header(header, isWrittenWith: key))
        #expect(BackupFile.header(rewrapped, isWrittenWith: key), "the same key under another passphrase is still ours")
        #expect(!BackupFile.header(other, isWrittenWith: key))
        #expect(!BackupFile.header(Data(repeating: 0, count: 10), isWrittenWith: key))
    }

    // MARK: Streaming

    @Test("a backup written chunk by chunk to a file is the same backup: it opens with both credentials")
    func whenStreamed_thenItOpensLikeAnyBackup() throws {
        let header = try BackupFile.makeHeader(key: key, passphrase: passphrase, iterations: 1000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stream-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try BackupFile.StreamingWriter(url: url, key: key, header: header)
        for record in records() {
            try writer.append(record)
        }
        let bytes = try writer.finish(origin: BackupOrigin(sequence: 9, deviceID: "mac-1", createdAt: createdAt))

        let data = try Data(contentsOf: url)
        #expect(bytes == data.count)
        #expect(try BackupFile.read(data, credential: .passphrase(passphrase)).records == records())
        #expect(try BackupFile.read(data, credential: .recoveryKey(key)).manifest.sequence == 9)
        #expect(try BackupFile.read(data, credential: .recoveryKey(key)).manifest.recordCount == 4)
    }

    @Test("a streamed file that was never finished has no manifest and is refused")
    func whenNotFinished_thenRefused() throws {
        let header = try BackupFile.makeHeader(key: key, passphrase: passphrase, iterations: 1000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stream-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try BackupFile.StreamingWriter(url: url, key: key, header: header)
        try writer.append(records()[0])
        writer.abandon()

        let data = (try? Data(contentsOf: url)) ?? Data()

        #expect(throws: BackupError.self) { try BackupFile.read(data, credential: .recoveryKey(key)) }
    }

    @Test("a header made for another key is refused when streaming starts")
    func whenStreamingWithTheWrongKey_thenRefused() throws {
        let header = try BackupFile.makeHeader(key: BackupKey.generate(), passphrase: passphrase, iterations: 1000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stream-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: BackupError.self) { try BackupFile.StreamingWriter(url: url, key: key, header: header) }
    }
}
