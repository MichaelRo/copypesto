// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

/// A segment file: `PSTOSEG1`, a random file id, then sealed chunks (one per record) and a sealed, signed manifest.
/// Each chunk is `length u32 | nonce 12 | ciphertext | tag 16`, sealed under a key derived from the sync key and the
/// file
/// id, bound to this file and to its position, so a chunk moved to another file or place does not open.
enum SyncSegmentFormat {
    static let magic = Data("PSTOSEG1".utf8)
    static let fileIDLength = 16
    static let maximumChunk = 64 << 20

    static func key(_ syncKey: SyncKey, fileID: Data) -> SymmetricKey {
        syncKey.subkey(salt: fileID, info: "pesto.sync.file.v1")
    }

    static func associatedData(fileID: Data, index: UInt32, isManifest: Bool) -> Data {
        var out = Data(SHA256.hash(data: magic + fileID))
        out.appendBigEndian(index)
        out.append(isManifest ? 1 : 0)
        return out
    }

    static func seal(_ plaintext: Data, key: SymmetricKey, fileID: Data, index: UInt32, isManifest: Bool) throws -> (
        chunk: Data, tag: Data
    ) {
        let box = try AES.GCM.seal(
            plaintext, using: key, authenticating: associatedData(fileID: fileID, index: index, isManifest: isManifest)
        )
        var chunk = Data()
        let body = box.nonce.withUnsafeBytes { Data($0) } + box.ciphertext + box.tag
        chunk.appendBigEndian(UInt32(body.count))
        chunk.append(body)
        return (chunk, Data(box.tag))
    }

    static func open(_ body: Data, key: SymmetricKey, fileID: Data, index: UInt32, isManifest: Bool) throws -> Data {
        guard body.count >= 28 else { throw SyncError.malformed("chunk") }
        let box = try AES.GCM.SealedBox(combined: body)
        do {
            return try AES.GCM.open(
                box, using: key, authenticating: associatedData(fileID: fileID, index: index, isManifest: isManifest)
            )
        } catch {
            throw SyncError.wrongKey
        }
    }
}

/// Writes a segment record by record to a `.partial` file and renames it when the manifest is down.
public final class SyncSegmentWriter {
    public struct Context {
        public var syncKey: SyncKey
        public var vaultID: Data
        public var epoch: UInt32
        public var deviceID: String
        public var device: SyncDeviceKeys
        public var previousManifestHash: String

        public init(
            syncKey: SyncKey, vaultID: Data, epoch: UInt32, deviceID: String, device: SyncDeviceKeys,
            previousManifestHash: String = SyncManifest.zeroHash
        ) {
            self.syncKey = syncKey
            self.vaultID = vaultID
            self.epoch = epoch
            self.deviceID = deviceID
            self.device = device
            self.previousManifestHash = previousManifestHash
        }
    }

    private let context: Context
    private let partialURL: URL
    private let handle: FileHandle
    private let fileID: Data
    private let key: SymmetricKey
    private var digest = SHA256()
    private var count = 0
    private var firstSequence: UInt64?
    private var lastSequence: UInt64 = 0

    public init(partialURL: URL, context: Context) throws {
        self.context = context
        self.partialURL = partialURL
        try? FileManager.default.removeItem(at: partialURL)
        guard FileManager.default.createFile(
            atPath: partialURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else { throw SyncError.malformed("cannot create segment") }
        handle = try FileHandle(forWritingTo: partialURL)
        fileID = Data((0..<SyncSegmentFormat.fileIDLength).map { _ in UInt8.random(in: 0...255) })
        key = SyncSegmentFormat.key(context.syncKey, fileID: fileID)
        try handle.write(contentsOf: SyncSegmentFormat.magic + fileID)
    }

    public func append(_ record: SyncRecord) throws {
        if let last = firstSequence.map({ _ in lastSequence }), record.sequence != last + 1 {
            throw SyncError.malformed("sequence gap")
        }
        let sealed = try SyncSegmentFormat.seal(
            record.serialized(), key: key, fileID: fileID, index: UInt32(count), isManifest: false
        )
        try handle.write(contentsOf: sealed.chunk)
        digest.update(data: sealed.tag)
        firstSequence = firstSequence ?? record.sequence
        lastSequence = record.sequence
        count += 1
    }

    /// Seals the manifest, flushes, and moves the file to `finalURL`. Returns the manifest, whose hash chains the next.
    @discardableResult
    public func finish(to finalURL: URL, now: Date = .now) throws -> SyncManifest {
        guard let first = firstSequence else { throw SyncError.malformed("empty segment") }
        let manifest = try SyncManifest(
            vaultID: context.vaultID.hexString, deviceID: context.deviceID, epoch: context.epoch,
            firstSequence: first, lastSequence: lastSequence, recordCount: count,
            bodyDigest: Data(digest.finalize()).hexString, previousManifestHash: context.previousManifestHash,
            createdAt: now, signerKeyID: context.device.publicKeys.keyID
        ).signed(by: context.device)
        let sealed = try SyncSegmentFormat.seal(
            SyncManifest.canonical(manifest), key: key, fileID: fileID, index: UInt32(count), isManifest: true
        )
        try handle.write(contentsOf: sealed.chunk)
        try handle.synchronize()
        try handle.close()
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.moveItem(at: partialURL, to: finalURL)
        return manifest
    }

    public func abandon() {
        try? handle.close()
        try? FileManager.default.removeItem(at: partialURL)
    }
}

/// A segment whose every chunk opened, whose manifest is signed by a trusted device and whose digest matches.
public struct VerifiedSyncSegment: Sendable {
    public let manifest: SyncManifest
    private let chunks: [Data]

    init(manifest: SyncManifest, chunks: [Data]) {
        self.manifest = manifest
        self.chunks = chunks
    }

    public func records() throws -> [SyncRecord] {
        var expected = manifest.firstSequence
        return try chunks.map { plaintext in
            let record = try SyncRecord.parse(plaintext)
            guard record.sequence == expected, record.stamp.deviceID == manifest.deviceID else {
                throw SyncError.malformed("record out of order")
            }
            expected += 1
            return record
        }
    }
}

public enum SyncSegmentReader {
    /// Opens and authenticates a segment. A wrong key, a changed byte, a truncated file, a chunk moved from another
    /// file, a manifest signed by a device that is not trusted, or one for another vault or epoch, all throw.
    public static func verify(
        _ data: Data, syncKey: SyncKey, trust: SyncTrust, vaultID: Data, epoch: UInt32
    ) throws
    -> VerifiedSyncSegment {
        let header = SyncSegmentFormat.magic.count + SyncSegmentFormat.fileIDLength
        guard data.count > header, data.prefix(SyncSegmentFormat.magic.count) == SyncSegmentFormat.magic else {
            throw SyncError.malformed("not a segment")
        }
        let fileID = data.subdata(in: SyncSegmentFormat.magic.count..<header)
        let key = SyncSegmentFormat.key(syncKey, fileID: fileID)
        var reader = ByteReader(data.suffix(from: data.startIndex + header))
        var bodies: [Data] = []
        var tags = SHA256()
        var index: UInt32 = 0
        var manifestPlain: Data?
        var sawEnd = false
        while !sawEnd {
            let length = try Int(reader.u32())
            guard length >= 28,
                  length <= SyncSegmentFormat.maximumChunk else { throw SyncError.malformed("chunk length") }
            let body = try reader.bytes(length)
            if reader.isAtEnd {
                manifestPlain = try SyncSegmentFormat.open(
                    body,
                    key: key,
                    fileID: fileID,
                    index: index,
                    isManifest: true
                )
                sawEnd = true
            } else {
                try bodies.append(SyncSegmentFormat.open(
                    body,
                    key: key,
                    fileID: fileID,
                    index: index,
                    isManifest: false
                ))
                tags.update(data: body.suffix(16))
                index += 1
            }
        }
        guard let manifestPlain else { throw SyncError.malformed("no manifest") }
        let manifest = try SyncManifest.decode(manifestPlain)
        guard manifest.version == 1 else { throw SyncError.unsupportedVersion }
        guard manifest.vaultID == vaultID.hexString else { throw SyncError.wrongVault }
        guard manifest.epoch == epoch else { throw SyncError.wrongEpoch }
        try manifest.verify(trust: trust)
        guard manifest.recordCount == bodies.count, manifest.bodyDigest == Data(tags.finalize()).hexString else {
            throw SyncError.malformed("digest")
        }
        return VerifiedSyncSegment(manifest: manifest, chunks: bodies)
    }
}
