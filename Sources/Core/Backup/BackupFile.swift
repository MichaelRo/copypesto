// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Synchronization

public struct BackupRecord: Sendable, Equatable {
    public enum Kind: UInt8, Sendable {
        case item = 1
        case collection = 2
        case tombstone = 3
        /// The settings JSON of the Mac that wrote the file, kept whole in `metadata` for the app to read: the format
        /// does not know what a setting is. Absent from a file written before settings were carried.
        case settings = 4
    }

    public let kind: Kind
    public let metadata: Data
    public let payload: Data

    public init(kind: Kind, metadata: Data, payload: Data = Data()) {
        self.kind = kind
        self.metadata = metadata
        self.payload = payload
    }
}

public struct BackupManifest: Codable, Sendable, Equatable {
    public let recordCount: Int
    /// Rises with every backup a device writes, so restoring something older than local state can be flagged.
    public let sequence: UInt64
    public let deviceID: String
    public let createdAt: Date

    public init(recordCount: Int, sequence: UInt64, deviceID: String, createdAt: Date) {
        self.recordCount = recordCount
        self.sequence = sequence
        self.deviceID = deviceID
        self.createdAt = createdAt
    }
}

public struct BackupOrigin: Sendable, Equatable {
    public let sequence: UInt64
    public let deviceID: String
    public let createdAt: Date

    public init(sequence: UInt64, deviceID: String, createdAt: Date) {
        self.sequence = sequence
        self.deviceID = deviceID
        self.createdAt = createdAt
    }
}

public struct BackupContents: Sendable, Equatable {
    public let manifest: BackupManifest
    public let records: [BackupRecord]

    public init(manifest: BackupManifest, records: [BackupRecord]) {
        self.manifest = manifest
        self.records = records
    }
}

public enum BackupCredential: Sendable {
    case passphrase(String)
    case recoveryKey(BackupKey)
}

/// The on-disk backup format, version 1. Layout:
///
///     header : "PSTOBKUP" | version u16 | kdf u8 | iterations u32 | salt 16 | wrap nonce 12 | wrapped key 48 | key
/// check 32
///     file id: "PSTOFILE" | random 16                              (files written since ADR 0010; optional)
///     chunk  : length u32 | nonce 12 | ciphertext | tag 16      (repeated; the last chunk is the manifest)
///
/// Every chunk is AES-GCM under the backup key with `SHA256(header | file id) | index | isManifest` as associated
/// data, so a changed header, a reordered, dropped, duplicated or spliced chunk, or a missing manifest fails
/// authentication. A later backup reuses the header (so the passphrase need not be kept), which is why the header
/// alone cannot tell two files of one Mac apart: the file id does, so a chunk of last week's backup cannot be put
/// into this week's. A chunk's length begins with a byte no real length can (the marker reads as over a gigabyte),
/// so a file without an id, written before this, is told apart without a version change and still opens.
public enum BackupFile {
    static let magic = Data("PSTOBKUP".utf8)
    static let version: UInt16 = 1
    static let kdfPBKDF2SHA256: UInt8 = 1
    private static let saltLength = 16
    private static let nonceLength = 12
    private static let tagLength = 16
    static let sealedOverhead = nonceLength + tagLength
    private static let wrappedKeyLength = BackupKey.byteCount + tagLength
    static let keyCheckLength = 32
    static let prefixLength = 8 + 2 + 1 + 4 + saltLength
    static let headerLength = prefixLength + nonceLength + wrappedKeyLength + keyCheckLength
    static let maximumChunkLength = 1 << 30
    static let fileIDMarker = Data("PSTOFILE".utf8)
    static let fileIDLength = 16
    static let fileIDBlockLength = fileIDMarker.count + fileIDLength

    public static func write(
        records: [BackupRecord],
        origin: BackupOrigin,
        key: BackupKey,
        passphrase: String,
        iterations: Int = BackupKeyDerivation.defaultIterations
    )
    throws -> Data {
        let header = try makeHeader(key: key, passphrase: passphrase, iterations: iterations)
        return try write(records: records, origin: origin, key: key, header: header)
    }

    /// The header of an existing backup (everything before the first chunk), or nil if the data is not one. A later
    /// backup can reuse it, so it can be written without asking for the passphrase again.
    public static func header(of data: Data) -> Data? {
        let data = Data(data)
        guard data.count >= headerLength, data.prefix(magic.count) == magic,
              data.bigEndianUInt16(at: 8) == version else { return nil }
        return Data(data.prefix(headerLength))
    }

    /// What follows the header: the hash every chunk is bound to, and where the first chunk starts. `following` is the
    /// bytes after the header (at least `fileIDBlockLength` of them when the file has that many).
    static func chunkBinding(header: Data, following: Data) -> (hash: Data, start: Int) {
        let following = Data(following)
        guard following.count >= fileIDBlockLength, following.prefix(fileIDMarker.count) == fileIDMarker else {
            return (Data(SHA256.hash(data: header)), headerLength)
        }
        let block = Data(following.prefix(fileIDBlockLength))
        return (Data(SHA256.hash(data: header + block)), headerLength + fileIDBlockLength)
    }

    /// Where the first chunk of `data` starts.
    static func firstChunkOffset(in data: Data) -> Int {
        let data = Data(data)
        guard data.count >= headerLength else { return headerLength }
        return chunkBinding(
            header: Data(data.prefix(headerLength)),
            following: Data(data.dropFirst(headerLength).prefix(fileIDBlockLength))
        ).start
    }

    private static func newFileIDBlock() -> Data {
        fileIDMarker + Data((0..<fileIDLength).map { _ in UInt8.random(in: .min ... .max) })
    }

    private struct StreamingState {
        var count: UInt32 = 0
        var bytes = 0
    }

    /// Writes a backup to a file one record at a time, so the whole history is never held in memory at once. The file
    /// is
    /// the same format `read` opens; without `finish` it has no manifest and is refused.
    public final class StreamingWriter: Sendable {
        private let handle: FileHandle
        private let key: BackupKey
        private let headerHash: Data
        private let state = Mutex(StreamingState())

        public init(url: URL, key: BackupKey, header: Data) throws {
            guard header.count == BackupFile.headerLength,
                  header.prefix(BackupFile.magic.count) == BackupFile.magic else { throw BackupError.notABackup }
            guard BackupFile.header(header, isWrittenWith: key) else { throw BackupError.wrongCredential }
            guard FileManager.default.createFile(
                atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]
            ) else { throw CocoaError(.fileWriteUnknown) }
            handle = try FileHandle(forWritingTo: url)
            self.key = key
            let block = BackupFile.newFileIDBlock()
            headerHash = Data(SHA256.hash(data: header + block))
            try handle.write(contentsOf: header + block)
            state.withLock { $0.bytes = header.count + block.count }
        }

        public func append(_ record: BackupRecord) throws {
            let index = state.withLock { $0.count }
            let framed = try BackupFile.chunk(record: record, index: index, headerHash: headerHash, key: key)
            try handle.write(contentsOf: framed)
            state.withLock {
                $0.count += 1
                $0.bytes += framed.count
            }
        }

        /// Writes the manifest, closes the file and returns its size.
        public func finish(origin: BackupOrigin) throws -> Int {
            let count = state.withLock { $0.count }
            let manifest = BackupManifest(
                recordCount: Int(count), sequence: origin.sequence, deviceID: origin.deviceID,
                createdAt: origin.createdAt
            )
            let framed = try BackupFile.sealChunk(
                JSONEncoder.backup.encode(manifest), index: count, isManifest: true, headerHash: headerHash, key: key
            )
            try handle.write(contentsOf: framed)
            try handle.synchronize()
            try handle.close()
            return state.withLock { $0.bytes + framed.count }
        }

        /// Stops without a manifest, leaving a file `read` refuses; the caller deletes it.
        public func abandon() {
            try? handle.close()
        }
    }

    /// Whether `header` was made with `key`, checked without opening the file. The same key under another passphrase
    /// counts: it is still this Mac's backup.
    public static func header(_ header: Data, isWrittenWith key: BackupKey) -> Bool {
        guard header.count == headerLength, header.prefix(magic.count) == magic else { return false }
        return Data(header.suffix(keyCheckLength)) == keyCheck(key: key, header: Data(header.dropLast(keyCheckLength)))
    }

    /// Writes a backup under a header made earlier by this key: the header carries the key wrapped by the passphrase,
    /// so
    /// the file opens with that passphrase or with the recovery key. A header made for another key is refused.
    public static func write(
        records: [BackupRecord],
        origin: BackupOrigin,
        key: BackupKey,
        header: Data
    ) throws
    -> Data {
        guard header.count == headerLength, header.prefix(magic.count) == magic else { throw BackupError.notABackup }
        let expected = keyCheck(key: key, header: Data(header.dropLast(keyCheckLength)))
        guard Data(header.suffix(keyCheckLength)) == expected else { throw BackupError.wrongCredential }
        return try body(records: records, origin: origin, key: key, header: header)
    }

    public static func makeHeader(
        key: BackupKey,
        passphrase: String,
        iterations: Int = BackupKeyDerivation.defaultIterations
    )
    throws -> Data {
        let salt = Data((0..<saltLength).map { _ in UInt8.random(in: .min ... .max) })
        var header = Data()
        header.append(magic)
        header.append(bigEndian: version)
        header.append(kdfPBKDF2SHA256)
        header.append(bigEndian: UInt32(iterations))
        header.append(salt)
        guard let wrapping = BackupKeyDerivation.pbkdf2SHA256(
            passphrase: passphrase,
            salt: salt,
            iterations: iterations
        ) else { throw BackupError.corrupted }
        let wrapped = try AES.GCM.seal(key.bytes, using: wrapping, authenticating: header)
        header.append(Data(wrapped.nonce))
        header.append(Data(wrapped.ciphertext))
        header.append(Data(wrapped.tag))
        header.append(keyCheck(key: key, header: header))
        return header
    }

    /// `fileID` is nil only to write the layout from before file ids, which a test needs to prove it still opens.
    static func body(
        records: [BackupRecord],
        origin: BackupOrigin,
        key: BackupKey,
        header: Data,
        fileID: Data? = newFileIDBlock()
    ) throws
    -> Data {
        var output = header
        let headerHash = Data(SHA256.hash(data: header + (fileID ?? Data())))
        if let fileID { output.append(fileID) }
        for (index, record) in records.enumerated() {
            try output.append(chunk(record: record, index: UInt32(index), headerHash: headerHash, key: key))
        }
        let manifest = BackupManifest(
            recordCount: records.count, sequence: origin.sequence, deviceID: origin.deviceID,
            createdAt: origin.createdAt
        )
        let manifestData = try JSONEncoder.backup.encode(manifest)
        try output.append(sealChunk(
            manifestData,
            index: UInt32(records.count),
            isManifest: true,
            headerHash: headerHash,
            key: key
        ))
        return output
    }

    /// Decrypts and authenticates the whole file before returning anything; a single bad byte fails the lot.
    public static func read(_ data: Data, credential: BackupCredential) throws -> BackupContents {
        let data = Data(data)
        guard data.count >= headerLength, data.prefix(magic.count) == magic else { throw BackupError.notABackup }
        let header = Data(data.prefix(headerLength))
        let (key, _) = try authenticate(header: header, credential: credential)
        let (headerHash, start) = chunkBinding(
            header: header, following: Data(data.dropFirst(headerLength).prefix(fileIDBlockLength))
        )

        var offset = start
        var records: [BackupRecord] = []
        var index: UInt32 = 0
        while offset < data.count {
            guard offset + 4 <= data.count else { throw BackupError.corrupted }
            let length = Int(data.bigEndianUInt32(at: offset))
            offset += 4
            guard length >= nonceLength + tagLength, length <= maximumChunkLength,
                  offset + length <= data.count else { throw BackupError.corrupted }
            let sealed = Data(data[offset..<offset + length])
            offset += length
            let isLast = offset == data.count
            let plaintext = try open(sealed, index: index, isManifest: isLast, headerHash: headerHash, key: key)
            if isLast {
                let manifest = try JSONDecoder.backup.decode(BackupManifest.self, from: plaintext)
                guard manifest.recordCount == records.count else { throw BackupError.corrupted }
                return BackupContents(manifest: manifest, records: records)
            }
            try records.append(decodeRecord(plaintext))
            index += 1
        }
        throw BackupError.corrupted
    }

    /// The key a header opens to under `credential`, and the hash every chunk is bound to. Checks the format fields
    /// first, so a file from a newer version or with an absurd iteration count is refused before any key derivation.
    static func authenticate(header: Data, credential: BackupCredential) throws -> (key: BackupKey, hash: Data) {
        let fileVersion = header.bigEndianUInt16(at: 8)
        guard fileVersion == version else { throw BackupError.unsupportedVersion(Int(fileVersion)) }
        guard header[10] == kdfPBKDF2SHA256 else { throw BackupError.corrupted }
        let iterations = Int(header.bigEndianUInt32(at: 11))
        guard (1...BackupKeyDerivation.maximumIterations).contains(iterations) else { throw BackupError.corrupted }
        let key = try resolveKey(credential, header: header, iterations: iterations)
        let expectedCheck = keyCheck(key: key, header: Data(header.dropLast(keyCheckLength)))
        guard Data(header.suffix(keyCheckLength)) == expectedCheck else { throw BackupError.wrongCredential }
        return (key, Data(SHA256.hash(data: header)))
    }

    // MARK: - Private

    private static func resolveKey(_ credential: BackupCredential, header: Data, iterations: Int) throws -> BackupKey {
        switch credential {
        case let .recoveryKey(key):
            return key
        case let .passphrase(passphrase):
            let salt = Data(header[(prefixLength - saltLength)..<prefixLength])
            guard let wrapping = BackupKeyDerivation.pbkdf2SHA256(
                passphrase: passphrase, salt: salt, iterations: iterations
            ) else { throw BackupError.corrupted }
            let nonceRange = prefixLength..<prefixLength + nonceLength
            let wrappedRange = nonceRange.upperBound..<nonceRange.upperBound + wrappedKeyLength
            do {
                let wrappedKey = Data(header[wrappedRange])
                let box = try AES.GCM.SealedBox(
                    nonce: AES.GCM.Nonce(data: Data(header[nonceRange])),
                    ciphertext: Data(wrappedKey.prefix(BackupKey.byteCount)),
                    tag: Data(wrappedKey.suffix(tagLength))
                )
                let keyBytes = try AES.GCM.open(box, using: wrapping, authenticating: Data(header.prefix(prefixLength)))
                return BackupKey(symmetricKey: SymmetricKey(data: keyBytes))
            } catch {
                throw BackupError.wrongCredential
            }
        }
    }

    private static func keyCheck(key: BackupKey, header: Data) -> Data {
        var message = Data("pesto-backup-key-check".utf8)
        message.append(header)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key.symmetricKey))
    }

    private static func chunk(record: BackupRecord, index: UInt32, headerHash: Data, key: BackupKey) throws -> Data {
        var plaintext = Data([record.kind.rawValue])
        plaintext.append(bigEndian: UInt32(record.metadata.count))
        plaintext.append(record.metadata)
        plaintext.append(record.payload)
        return try sealChunk(plaintext, index: index, isManifest: false, headerHash: headerHash, key: key)
    }

    private static func sealChunk(
        _ plaintext: Data,
        index: UInt32,
        isManifest: Bool,
        headerHash: Data,
        key: BackupKey
    )
    throws -> Data {
        let aad = associatedData(headerHash: headerHash, index: index, isManifest: isManifest)
        let box = try AES.GCM.seal(plaintext, using: key.symmetricKey, authenticating: aad)
        var sealed = Data(box.nonce)
        sealed.append(box.ciphertext)
        sealed.append(box.tag)
        var framed = Data()
        framed.append(bigEndian: UInt32(sealed.count))
        framed.append(sealed)
        return framed
    }

    static func open(
        _ sealed: Data,
        index: UInt32,
        isManifest: Bool,
        headerHash: Data,
        key: BackupKey
    ) throws
    -> Data {
        let aad = associatedData(headerHash: headerHash, index: index, isManifest: isManifest)
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: Data(sealed.prefix(nonceLength))),
                ciphertext: Data(sealed.dropFirst(nonceLength).dropLast(tagLength)),
                tag: Data(sealed.suffix(tagLength))
            )
            return try AES.GCM.open(box, using: key.symmetricKey, authenticating: aad)
        } catch {
            throw BackupError.corrupted
        }
    }

    private static func associatedData(headerHash: Data, index: UInt32, isManifest: Bool) -> Data {
        var aad = headerHash
        aad.append(bigEndian: index)
        aad.append(isManifest ? 1 : 0)
        return aad
    }

    /// The kind of a decrypted record, after the same checks `decodeRecord` makes, without copying its payload.
    static func validatedKind(_ plaintext: Data) throws -> BackupRecord.Kind {
        guard plaintext.count >= 5, let kind = BackupRecord.Kind(rawValue: plaintext[0]),
              5 + Int(plaintext.bigEndianUInt32(at: 1)) <= plaintext.count else { throw BackupError.corrupted }
        return kind
    }

    static func decodeRecord(_ plaintext: Data) throws -> BackupRecord {
        let kind = try validatedKind(plaintext)
        let metadataLength = Int(plaintext.bigEndianUInt32(at: 1))
        return BackupRecord(
            kind: kind,
            metadata: Data(plaintext[5..<5 + metadataLength]),
            payload: Data(plaintext[(5 + metadataLength)...])
        )
    }
}

extension Data {
    mutating func append(bigEndian value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8((value >> (24 - 8 * UInt32($0))) & 0xFF) })
    }

    func bigEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) << 8 | UInt16(self[startIndex + offset + 1])
    }

    func bigEndianUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 << 8 | UInt32(self[startIndex + offset + $1]) }
    }
}

extension JSONEncoder {
    static var backup: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var backup: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
