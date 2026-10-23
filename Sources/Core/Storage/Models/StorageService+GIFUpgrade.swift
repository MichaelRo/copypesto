// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

extension StorageService {
    /// Largest GIF kept in place of a still picture (the same bound a link preview uses).
    static let largestUpgradedGIFBytes = 16 * 1024 * 1024

    /// Starts the fetch for a clip saved from a still picture and the address of its GIF. Tracked, so
    /// `waitForBackgroundWork()` waits for it.
    func startGIFUpgrade(of itemID: UUID, from address: URL) {
        guard let fetcher = remoteGIFFetcher else { return }
        let taskID = UUID()
        pendingAnalyses[taskID] = Task.detached(priority: .utility) { [self] in
            let fetching = PerfSignposts.copy.begin("gifUpgrade")
            if let data = await fetcher(address) { await upgrade(itemID, toGIF: data) }
            fetching.end()
            await endAnalysis(taskID)
        }
    }

    /// Stores the GIF as the clip's data, so the card plays it and a paste carries it. Anything that is not a GIF, or
    /// is
    /// too large, or arrives for a clip that has gone, changes nothing.
    func upgrade(_ itemID: UUID, toGIF data: Data) {
        guard data.isGIF, data.count <= Self.largestUpgradedGIFBytes else { return }
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == itemID })
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first, item.type == .image,
              let blob = item.blob, blob.mimeType != "com.compuserve.gif" else { return }
        do {
            let envelope = try encryption.encrypt(
                data, associatedData: BlobEncryption.associatedData(itemID: itemID, field: .blob)
            )
            blob.encryptedData = envelope.ciphertext
            blob.nonceData = envelope.nonce
            blob.mimeType = "com.compuserve.gif"
            blob.aadBound = true
            item.byteSize = data.count
            try saveOrRollback()
        } catch {
            Self.analysisLogger.error("GIF not stored: \(error.localizedDescription, privacy: .public)")
        }
    }
}
