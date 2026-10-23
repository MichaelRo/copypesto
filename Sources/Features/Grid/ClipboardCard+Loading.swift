// SPDX-License-Identifier: MIT
import AppKit
import os
import PestoCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What the card's loading task depends on: the clip, whether it is still waiting to be judged (a picture is not
/// decoded
/// while it is covered), and its size (a still picture that becomes its GIF has another, and is loaded again).
struct CardLoadKey: Hashable {
    let id: UUID
    let isPending: Bool
    let byteSize: Int
}

// MARK: - Thumbnail loading

let cardLoadingLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "CardLoading")

extension ClipboardCard {
    func loadThumbnailIfNeeded() async {
        PerfSignposts.shelf.event("cardAppear", item.id.uuidString)
        let byteSize = item.byteSize
        guard item.type == .image || item.isSVGSource, thumbnail == nil || thumbnailByteSize != byteSize,
              !item.analysisPending else { return }
        defer { PerfSignposts.shelf.event("cardThumbnail", item.id.uuidString) }
        let id = item.id
        if let cached = ThumbnailCache.shared.entry(for: id, byteSize: byteSize) {
            thumbnail = cached.image
            thumbnailIsAnimated = cached.isAnimated
            thumbnailByteSize = byteSize
            return
        }
        let service = ThumbnailService(modelContainer: modelContext.container)
        // Twice the card width covers a Retina display; the full-resolution bitmap is never decoded.
        guard let result = await service.thumbnail(for: id, maxPixel: 480),
              let image = await PreparedImage.image(from: result.data, animated: result.isAnimated) else { return }
        ThumbnailCache.shared.store(.init(image: image, isAnimated: result.isAnimated, byteSize: byteSize), for: id)
        thumbnail = image
        thumbnailIsAnimated = result.isAnimated
        thumbnailByteSize = byteSize
    }

    func storeFetched(_ result: URLPreviewResult, storedImage: Data?, itemID: UUID) {
        if item.ogTitle != result.title { item.ogTitle = result.title }
        if item.ogSiteName != result.siteName { item.ogSiteName = result.siteName }
        if item.ogImageThumbnail != nil { item.ogImageThumbnail = nil }
        if let data = result.ogImageData, data != storedImage {
            Task.detached(priority: .utility) {
                do {
                    try LinkPreviewImageStore().save(data, for: itemID)
                } catch {
                    cardLoadingLogger
                        .error("A link preview picture was not saved: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func loadURLMetadataIfNeeded() async {
        guard item.type == .url, LinkPreviewPolicy.isEnabled(), previewsAllowed, item.sensitivityRaw == nil,
              let link = URL(string: item.displayPreviewText), LinkPreviewEligibility.isEligible(link) else { return }
        // Decode the stored OG image (persisted from a previous fetch). Rows saved before the image store
        // existed still carry it inline until the launch-time migration moves it.
        let itemID = item.id
        let stored = await Task.detached(priority: .utility) { LinkPreviewImageStore().load(for: itemID) }.value
        if let data = item.ogImageThumbnail ?? stored {
            urlOGImage = await PreparedImage.image(from: data, animated: data.isGIF)
            urlOGImageIsAnimated = data.isGIF
        }
        // Populate favicon from cache or from stored OG image metadata.
        guard let url = URL(string: item.displayPreviewText) else { return }
        if urlFavicon == nil, let cachedEntry = LinkPreviewCache.shared.entry(for: url),
           let data = cachedEntry.faviconData
        {
            urlFavicon = await PreparedImage.image(from: data)
        }
        if !item.linkPreviewFetched, item.ogTitle != nil || item.ogSiteName != nil || stored != nil {
            derive { $0.linkPreviewFetched = true }
        }
        guard !item.linkPreviewFetched else { return }

        // Fetch metadata if we don't have anything yet (first time this item is seen).
        let fetchResult = try? await URLMetadataFetcher.shared.fetch(url: url)
        derive { $0.linkPreviewFetched = true }
        guard let result = fetchResult else { return }
        guard !Task.isCancelled else { return }
        await applyFetchedPreview(result, stored: stored, itemID: itemID)
    }

    private func applyFetchedPreview(_ result: URLPreviewResult, stored: Data?, itemID: UUID) async {
        var explicit = false
        if nsfwMode.detectsContent, !item.isNSFW {
            let signals = NSFWURLDetector.LinkPreviewSignals(
                title: result.title,
                description: nil,
                siteName: result.siteName
            )
            explicit = NSFWURLDetector.isExplicit(urlString: item.displayPreviewText, metadata: signals)
        }
        if nsfwMode.detectsContent, !item.isNSFW, !explicit, stored == nil, let data = result.ogImageData {
            explicit = await OnDeviceImageScreener().isSensitive(imageData: data)
        }
        derive(flagsContent: explicit) {
            storeFetched(result, storedImage: stored, itemID: itemID)
            if explicit { $0.isNSFW = true }
        }
        if let data = result.ogImageData, data != stored || urlOGImage == nil {
            urlOGImage = await PreparedImage.image(from: data, animated: data.isGIF)
            urlOGImageIsAnimated = data.isGIF
        }
        if urlFavicon == nil, let data = result.faviconData { urlFavicon = await PreparedImage.image(from: data) }
    }

    /// A change that came from a fetch, not from the person: saved through the shelf's editor so a failure is not
    /// silent, and kept out of Undo. Flagging a card as explicit is a protection, so that failure is shown.
    private func derive(flagsContent: Bool = false, _ change: (ClipboardItem) -> Void) {
        if let clipEditor {
            clipEditor.applyDerived(to: item, changesFilter: flagsContent, reportsFailure: flagsContent, change)
        } else {
            change(item)
            do {
                try modelContext.saveOrRollback()
            } catch {
                cardLoadingLogger
                    .error("A derived change was not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
