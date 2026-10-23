// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

extension StorageService {
    /// When this content is already in the history, moves that clip to the front (and records where it was copied
    /// from) instead of storing a second one. True when it did.
    func popExistingDuplicate(
        matching descriptor: FetchDescriptor<ClipboardItem>,
        hash: String,
        now: Date,
        bundleID: String?,
        isRemote: Bool? = nil
    ) async throws
    -> Bool {
        guard let existing = try modelContext.fetch(descriptor).first else { return false }
        existing.contentHash = hash // upgrades an item stored under the old plain hash
        existing.timestamp = now
        lastIngestedHash = (hash, now)
        lastInsertedClip = nil
        if let isRemote {
            existing.isRemote = isRemote
            if isRemote {
                existing.sourceBundleID = nil
                existing.sourceAppName = PasteboardCapture.remoteSourceName
                existing.sourceDominantColorHex = nil
            }
        }
        if let bundleID {
            let appRecord = await resolver.resolve(bundleID: bundleID)
            existing.sourceBundleID = bundleID
            existing.sourceAppName = appRecord.displayName
            existing.sourceDominantColorHex = appRecord.dominantColorHex
        }
        try saveOrRollback()
        return true
    }

    func perceptualDuplicate(of candidateHash: String, payload: Data) -> ClipboardItem? {
        let imageTypeRaw = ClipboardType.image.rawValue
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.typeRaw == imageTypeRaw },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        guard let recent = try? modelContext.fetch(descriptor) else { return nil }
        let nominatedIDs = Set(PerceptualHasher.nominees(
            for: candidateHash, among: recent.map { (id: $0.id, hash: $0.perceptualHash) }
        ))
        let nominated = recent.filter { nominatedIDs.contains($0.id) }
        guard !nominated.isEmpty, let digest = PerceptualHasher.pixelDigest(imageData: payload) else { return nil }
        return nominated.first { item in
            item.blob?.decryptedData().flatMap { PerceptualHasher.pixelDigest(imageData: $0) } == digest
        }
    }
}
