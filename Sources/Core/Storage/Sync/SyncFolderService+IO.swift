// SPDX-License-Identifier: MIT
import Foundation

extension SyncFolderService {
    struct WriteContext {
        let found: SyncGroup
        let layout: SyncFolderLayout
        let identity: SyncIdentity
        let folderProbe: FolderProbe
        let now: @Sendable () -> Date
    }

    @concurrent
    static func rootExists(at path: String) async -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    @concurrent
    static func openGroupOffMain(
        layout: SyncFolderLayout, keyStore: any SyncKeyStoring, preferring joined: Data?
    ) async throws
    -> SyncGroupOpening {
        try SyncGroupManager.open(layout: layout, keyStore: keyStore, preferring: joined)
    }

    @concurrent
    static func recoverOwnLogOffMain(
        layout: SyncFolderLayout,
        deviceID: String,
        found: SyncGroup,
        isReadable: @Sendable (URL) -> Bool
    ) async throws
    -> (sequence: UInt64, hash: String)?? {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: layout.log(deviceID).path)) ?? [])
            .filter { $0.hasSuffix(".pestolog") }.sorted()
        guard let last = names.last, let range = sequenceRange(of: last) else {
            return .some(nil)
        }
        let url = layout.log(deviceID).appendingPathComponent(last)
        guard isReadable(url), let data = try? Data(contentsOf: url) else { return nil }
        var hash = SyncManifest.zeroHash
        do {
            let verified = try SyncSegmentReader.verify(
                data, syncKey: found.key, trust: found.trust, vaultID: found.vault.vaultID, epoch: found.epoch
            )
            hash = try verified.manifest.hash()
        } catch SyncError.wrongEpoch {
            hash = SyncManifest.zeroHash
        }
        return .some((range.last, hash))
    }

    @concurrent
    static func writeSegmentOffMain(
        outbox: SyncOutbox,
        context: WriteContext,
        ownLast: (sequence: UInt64, hash: String),
        snapshot: Bool
    ) async throws
    -> (sequence: UInt64, hash: String) {
        try writeBlobsOffMain(
            outbox.blobs, context.found, layout: context.layout,
            deviceID: context.identity.deviceID, folderProbe: context.folderProbe
        )
        let first = ownLast.sequence + 1
        let last = first + UInt64(outbox.records.count) - 1
        let url = context.layout.segment(context.identity.deviceID, first: first, last: last)
        try FileManager.default.createDirectory(
            at: context.layout.log(context.identity.deviceID),
            withIntermediateDirectories: true
        )
        let writer = try SyncSegmentWriter(partialURL: url.appendingPathExtension("partial"), context: .init(
            syncKey: context.found.key, vaultID: context.found.vault.vaultID, epoch: context.found.epoch,
            deviceID: context.identity.deviceID, device: context.identity.keys,
            previousManifestHash: ownLast.hash, isSnapshot: snapshot
        ))
        do {
            for (offset, record) in outbox.records.enumerated() {
                var numbered = record
                numbered.sequence = first + UInt64(offset)
                try writer.append(numbered)
            }
            try context.folderProbe.willWrite(url)
            let manifest = try writer.finish(to: url, now: context.now())
            return try (last, manifest.hash())
        } catch {
            writer.abandon()
            throw error
        }
    }

    nonisolated static func writeBlobsOffMain(
        _ blobs: [String: Data],
        _ found: SyncGroup,
        layout: SyncFolderLayout,
        deviceID: String,
        folderProbe: FolderProbe
    ) throws {
        guard !blobs.isEmpty else { return }
        try FileManager.default.createDirectory(at: layout.blobs(deviceID), withIntermediateDirectories: true)
        for (name, payload) in blobs {
            let url = layout.blobs(deviceID).appendingPathComponent(SyncBlobFile.fileName(name))
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try folderProbe.willWrite(url)
            try folderProbe.writeData(SyncBlobFile.seal(payload, name: name, syncKey: found.key), url)
        }
    }

    @concurrent
    static func writeHeadOffMain(
        context: WriteContext,
        ownLast: (sequence: UInt64, hash: String),
        cursors: [String: UInt64]
    ) async throws {
        let head = SyncHead(
            deviceID: context.identity.deviceID, epoch: context.found.epoch, lastSequence: ownLast.sequence,
            lastManifestHash: ownLast.hash, cursors: cursors, writtenAt: context.now(),
            signerKeyID: context.identity.keys.publicKeys.keyID
        )
        let url = context.layout.head(context.identity.deviceID)
        try context.folderProbe.willWrite(url)
        try context.folderProbe.writeData(
            head.sealed(syncKey: context.found.key, signedBy: context.identity.keys), url
        )
    }

    @concurrent
    static func pendingSegmentsOffMain(logDirectory: String, after done: UInt64) async -> [String] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: logDirectory)) ?? [])
            .filter { $0.hasSuffix(".pestolog") }.sorted()
        return names.filter { (sequenceRange(of: $0)?.last ?? 0) > done }
    }

    @concurrent
    static func verifySegmentOffMain(
        url: URL, found: SyncGroup, isReadable: @Sendable (URL) -> Bool
    ) async throws
    -> VerifiedSyncSegment?? {
        guard isReadable(url), let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try .some(SyncSegmentReader.verify(
                data, syncKey: found.key, trust: found.trust, vaultID: found.vault.vaultID, epoch: found.epoch
            ))
        } catch SyncError.wrongEpoch {
            return .some(nil)
        }
    }

    @concurrent
    static func loadSegmentPayloadsOffMain(
        verified: VerifiedSyncSegment,
        layout: SyncFolderLayout,
        device: String,
        found: SyncGroup,
        isReadable: @Sendable (URL) -> Bool
    ) async throws
    -> ([SyncRecord], [String: Data])? {
        let records = try verified.records()
        var out: [String: Data] = [:]
        for record in records where record.kind == .item {
            guard let name = try record.decodeMetadata(SyncItemRecord.self).blobName else { continue }
            let url = layout.blobs(device).appendingPathComponent(SyncBlobFile.fileName(name))
            guard isReadable(url), let data = try? Data(contentsOf: url) else { return nil }
            out[name] = try SyncBlobFile.open(data, name: name, syncKey: found.key)
        }
        return (records, out)
    }
}
