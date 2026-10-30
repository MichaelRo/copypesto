// SPDX-License-Identifier: MIT
import Foundation

extension SyncFolderService {
    /// A long log is replaced by a snapshot: this Mac sends again, with their own stamps, everything it last changed
    /// (a record applied twice changes nothing), then removes the segments before it. A Mac that is still behind jumps
    /// to the snapshot (`SyncHighWater`), one that joins reads from it, and the files of clips that are gone with it.
    func compactIfNeeded(_ found: SyncGroup) async throws {
        let names = ownSegmentNames()
        guard names.count > max(timing.compactAfterSegments, 2 * segmentsAfterCompaction) else { return }
        let snapshotStart = ownLast.sequence + 1
        guard try await storage.markOwnForSnapshot(deviceID: identity.deviceID, now: now()) > 0 else { return }
        try await write(found, snapshot: true)
        guard ownLast.sequence >= snapshotStart else { return }
        for name in names {
            guard let last = Self.sequenceRange(of: name)?.last, last < snapshotStart else { continue }
            try? FileManager.default.removeItem(at: layout.log(identity.deviceID).appendingPathComponent(name))
        }
        removeUnreferencedBlobs(found)
        segmentsAfterCompaction = ownSegmentNames().count
    }

    private func ownSegmentNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: layout.log(identity.deviceID).path)) ?? [])
            .filter { $0.hasSuffix(".pestolog") }.sorted()
    }

    private func removeUnreferencedBlobs(_ found: SyncGroup) {
        var referenced: Set<String> = []
        for name in ownSegmentNames() {
            let url = layout.log(identity.deviceID).appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), let verified = try? SyncSegmentReader.verify(
                data, syncKey: found.key, trust: found.trust, vaultID: found.vault.vaultID, epoch: found.epoch
            ), let records = try? verified.records() else { return }
            for record in records where record.kind == .item {
                if let blob = try? record.decodeMetadata(SyncItemRecord.self).blobName {
                    referenced.insert(SyncBlobFile.fileName(blob))
                }
            }
        }
        let folder = layout.blobs(identity.deviceID)
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            where file.hasSuffix(".pestoblob") && !referenced.contains(file)
        {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }
}
