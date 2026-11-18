// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import UIKit

/// A picture clip's picture (or a link's stored preview picture), made off the main thread by the store's one
/// `ThumbnailService` and decoded off it too. Card-sized pictures are kept in `ThumbnailCache`, so scrolling back to a
/// card does not open the picture again; the detail view's larger one is not.
enum CardMedia {
    static let cardPixel = 480

    struct Picture {
        let image: UIImage
        let isAnimated: Bool
    }

    @MainActor
    static func picture(itemID: UUID, byteSize: Int, container: ModelContainer?, maxPixel: Int) async -> Picture? {
        let caches = maxPixel <= cardPixel
        if caches, let cached = ThumbnailCache.shared.entry(for: itemID, byteSize: byteSize) {
            return Picture(image: cached.image, isAnimated: cached.isAnimated)
        }
        guard let container else { return nil }
        let service = await ThumbnailServices.shared.service(for: container)
        guard let thumbnail = await service.thumbnail(for: itemID, maxPixel: maxPixel),
              let image = await decode(thumbnail.data) else { return nil }
        if caches {
            ThumbnailCache.shared.store(
                .init(image: image, isAnimated: thumbnail.isAnimated, byteSize: byteSize), for: itemID
            )
        }
        return Picture(image: image, isAnimated: thumbnail.isAnimated)
    }

    @concurrent
    static func linkPicture(for itemID: UUID) async -> UIImage? {
        guard let data = LinkPreviewImageStore().load(for: itemID) else { return nil }
        return await decode(data)
    }

    @concurrent
    static func decode(_ data: Data) async -> UIImage? {
        await UIImage(data: data)?.byPreparingForDisplay()
    }
}

struct ClipThumbnail: View {
    let itemID: UUID
    let byteSize: Int
    let maxPixel: Int
    @Environment(MobileAppState.self) private var appState
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.12)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .accessibilityHidden(true)
        .task(id: itemID) {
            image = await CardMedia.picture(
                itemID: itemID, byteSize: byteSize, container: appState.historyContainer, maxPixel: maxPixel
            )?.image
        }
    }
}
