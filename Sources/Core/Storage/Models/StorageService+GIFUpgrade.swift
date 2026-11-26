// SPDX-License-Identifier: MIT
import Foundation
import os
import SwiftData

extension StorageService {
    /// Largest GIF kept in place of a still picture (the same bound a link preview uses).
    static let largestUpgradedGIFBytes = 16 * 1024 * 1024

    /// Starts the fetch for a clip saved from a still picture and the address of its GIF, once the still's verdict is
    /// in (ADR 0079). With `screens`, the still passed and the GIF is screened before it replaces it: a GIF the model
    /// flags is still kept, so Show plays it, and the clip is flagged. Tracked, so `waitForBackgroundWork()` waits for
    /// it.
    func startGIFUpgrade(of itemID: UUID, from address: URL, screens: Bool) {
        guard let fetcher = remoteGIFFetcher else { return }
        let screener = imageScreener
        let taskID = UUID()
        let task = Task.detached(priority: .utility) { [self] in
            let fetching = PerfSignposts.copy.begin("gifUpgrade")
            if !Task.isCancelled, let data = await fetcher(address), !Task.isCancelled {
                let flagged = screens ? await screener.isSensitive(imageData: data) : false
                if !Task.isCancelled {
                    await upgrade(itemID, toGIF: data, flagging: flagged)
                }
            }
            fetching.end()
            await endAnalysis(taskID, for: itemID)
        }
        trackBackgroundTask(taskID, for: itemID, in: &pendingAnalyses, task: task)
    }

    /// Stores the GIF as the clip's data, so the card plays it and a paste carries it. Anything that is not a GIF, or
    /// is
    /// too large, or arrives for a clip that has gone, changes nothing.
    func upgrade(_ itemID: UUID, toGIF fetched: Data, flagging flagged: Bool = false) {
        guard fetched.count <= Self.largestUpgradedGIFBytes,
              let data = fetched.isGIF ? fetched : ImageDownsampler.animatedGIF(
                  from: fetched,
                  maxPixel: 600,
                  maxFrames: 60
              ) else { return }
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
            if flagged { item.isNSFW = true }
            item.updateMetadata { $0.pictureFingerprint = nil }
            if let dimensions = ImageDownsampler.pixelDimensions(of: data) {
                item.pixelWidth = dimensions.width
                item.pixelHeight = dimensions.height
            }
            try saveOrRollback()
            ThumbnailService.invalidate(id: itemID)
        } catch {
            Self.analysisLogger.error("GIF not stored: \(error.localizedDescription, privacy: .public)")
        }
    }
}
