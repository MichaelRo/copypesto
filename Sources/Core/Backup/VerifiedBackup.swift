// SPDX-License-Identifier: MIT
import Darwin
import Foundation

struct BackupRecordCounts {
    var items = 0
    var collections = 0
    var deletions = 0
    var settings = 0

    var total: Int {
        items + collections + deletions + settings
    }
}

/// A backup file that has been authenticated end to end without being read into memory. It keeps the file open, so a
/// later backup replacing or deleting the file does not change what is restored, and hands the clips out one at a time,
/// authenticating each chunk again as it is read.
///
/// Only collections and deletions (few, by ADR 0010) are kept in memory; they must be applied before any clip. Use one
/// pass at a time.
public final class VerifiedBackup: Sendable {
    public let manifest: BackupManifest
    public let itemCount: Int
    public let collectionCount: Int
    public let deletionCount: Int
    public let smallRecords: [BackupRecord]
    /// The settings the file carries, or nil for a file that has none.
    public var settingsData: Data? {
        smallRecords.first { $0.kind == .settings }?.metadata
    }

    private let file: BackupReadableFile
    private let key: BackupKey
    private let headerHash: Data
    private let start: Int

    init(
        manifest: BackupManifest, counts: BackupRecordCounts, smallRecords: [BackupRecord],
        file: BackupReadableFile, key: BackupKey, headerHash: Data, start: Int
    ) {
        self.manifest = manifest
        itemCount = counts.items
        collectionCount = counts.collections
        deletionCount = counts.deletions
        self.smallRecords = smallRecords
        self.file = file
        self.key = key
        self.headerHash = headerHash
        self.start = start
    }

    /// Hands each clip to `body` in file order. Throws `BackupError.corrupted` if the file no longer matches what was
    /// verified; clips already handed over stay handed over, and restoring again picks up where it stopped.
    public func forEachItem(
        isolation _: isolated (any Actor)? = #isolation,
        _ body: (BackupRecord) async throws -> Void
    ) async throws {
        var reader = BackupChunkReader(file: file, headerHash: headerHash, key: key, start: start)
        while let chunk = try reader.next() {
            if chunk.isManifest {
                guard try JSONDecoder.backup.decode(BackupManifest.self, from: chunk.plaintext) == manifest else {
                    throw BackupError.corrupted
                }
                return
            }
            if try BackupFile.validatedKind(chunk.plaintext) == .item {
                try await body(BackupFile.decodeRecord(chunk.plaintext))
            }
        }
        throw BackupError.corrupted
    }
}

/// A backup file read with `pread` into a buffer that is freed at once. `FileHandle.read` keeps the pages it returned
/// resident (measured: an 80 MB file grew resident memory by 80 MB, against 2 to 6 MB with `pread`).
final class BackupReadableFile: Sendable {
    private let descriptor: Int32
    let size: UInt64

    init(url: URL) throws {
        descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            close(descriptor)
            throw error
        }
        size = UInt64(status.st_size)
    }

    deinit {
        close(descriptor)
    }

    /// Exactly `count` bytes at `offset`; a file that ends sooner has changed since it was measured.
    func read(_ count: Int, at offset: UInt64) throws -> Data {
        var data = Data(count: count)
        var done = 0
        while done < count {
            let received = data.withUnsafeMutableBytes { buffer in
                pread(descriptor, buffer.baseAddress.map { $0 + done }, count - done, off_t(offset) + off_t(done))
            }
            if received < 0 {
                if errno == EINTR { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            guard received > 0 else { throw BackupError.corrupted }
            done += received
        }
        return data
    }
}

struct BackupChunkReader {
    struct Chunk {
        let plaintext: Data
        let isManifest: Bool
    }

    let file: BackupReadableFile
    let headerHash: Data
    let key: BackupKey
    private var offset: UInt64
    private var index: UInt32 = 0

    init(file: BackupReadableFile, headerHash: Data, key: BackupKey, start: Int) {
        self.file = file
        self.headerHash = headerHash
        self.key = key
        offset = UInt64(start)
    }

    /// The next chunk, opened and authenticated, or nil at the end of the file. The chunk that ends the file is the
    /// manifest.
    mutating func next() throws -> Chunk? {
        guard offset < file.size else { return nil }
        guard offset + 4 <= file.size else { throw BackupError.corrupted }
        let length = try Int(file.read(4, at: offset).bigEndianUInt32(at: 0))
        guard length >= BackupFile.sealedOverhead, length <= BackupFile.maximumChunkLength,
              offset + 4 + UInt64(length) <= file.size else { throw BackupError.corrupted }
        let sealed = try file.read(length, at: offset + 4)
        offset += 4 + UInt64(length)
        let isManifest = offset == file.size
        let plaintext = try BackupFile.open(
            sealed, index: index, isManifest: isManifest, headerHash: headerHash, key: key
        )
        if !isManifest { index += 1 }
        return Chunk(plaintext: plaintext, isManifest: isManifest)
    }
}

public extension BackupFile {
    /// Pass one of a restore: authenticates every chunk and the manifest, counts the records and keeps the small ones,
    /// holding at most one chunk in memory. Refuses exactly what `read` refuses.
    static func verify(url: URL, credential: BackupCredential) throws -> VerifiedBackup {
        let file = try BackupReadableFile(url: url)
        guard file.size >= UInt64(headerLength) else { throw BackupError.notABackup }
        let header = try file.read(headerLength, at: 0)
        guard header.prefix(magic.count) == magic else { throw BackupError.notABackup }
        let (key, _) = try authenticate(header: header, credential: credential)
        let following = try file.read(
            min(fileIDBlockLength, Int(file.size) - headerLength), at: UInt64(headerLength)
        )
        let (headerHash, start) = chunkBinding(header: header, following: following)

        var reader = BackupChunkReader(file: file, headerHash: headerHash, key: key, start: start)
        var counts = BackupRecordCounts()
        var small: [BackupRecord] = []
        while let chunk = try reader.next() {
            if chunk.isManifest {
                let manifest = try JSONDecoder.backup.decode(BackupManifest.self, from: chunk.plaintext)
                guard manifest.recordCount == counts.total else {
                    throw BackupError.corrupted
                }
                return VerifiedBackup(
                    manifest: manifest, counts: counts, smallRecords: small, file: file, key: key,
                    headerHash: headerHash, start: start
                )
            }
            switch try validatedKind(chunk.plaintext) {
            case .item:
                counts.items += 1
            case .collection:
                counts.collections += 1
                try small.append(decodeRecord(chunk.plaintext))
            case .tombstone:
                counts.deletions += 1
                try small.append(decodeRecord(chunk.plaintext))
            case .settings:
                counts.settings += 1
                try small.append(decodeRecord(chunk.plaintext))
            }
        }
        throw BackupError.corrupted
    }
}
