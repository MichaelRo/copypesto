// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import UIKit

/// A picture clip's picture (or a link's stored preview picture), made off the main thread by the store's one
/// `ThumbnailService` and decoded off it too. Card-sized pictures are kept in `ThumbnailCache`, so scrolling back to a
/// card does not open the picture again; the detail view's larger one is not.
enum CardMedia {
    private final class BoxedAnimation {
        let animation: GIFFrames.Animation
        init(_ animation: GIFFrames.Animation) {
            self.animation = animation
        }
    }

    @MainActor private static let animationCache: NSCache<NSString, BoxedAnimation> = {
        let cache = NSCache<NSString, BoxedAnimation>()
        cache.countLimit = 12
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    @MainActor
    static func clearAnimationCache() {
        animationCache.removeAllObjects()
    }

    static let cardPixel = 480

    struct Picture {
        let image: UIImage
        let isAnimated: Bool
        var animation: GIFFrames.Animation?
    }

    /// A GIF's frames are decoded only when `frames` names a budget, from the service's small GIF (it caches it).
    @MainActor
    static func picture(
        itemID: UUID, byteSize: Int, container: ModelContainer?, maxPixel: Int, frames: GIFFrames.Budget? = nil
    ) async
    -> Picture? {
        let caches = maxPixel <= cardPixel
        if caches, let cached = ThumbnailCache.shared.entry(for: itemID, byteSize: byteSize),
           !(cached.isAnimated && frames != nil)
        {
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
        var picture = Picture(image: image, isAnimated: thumbnail.isAnimated)
        if thumbnail.isAnimated,
           let frames { picture.animation = await GIFFrames.decode(thumbnail.data, budget: frames) }
        return picture
    }

    /// The frames of a card's GIF, decoded behind `GIFDecodeGate` so a fast scroll decodes only a few at a time.
    @MainActor
    static func gifFrames(
        itemID: UUID, byteSize: Int = 0, container: ModelContainer?, budget: GIFFrames.Budget
    ) async
    -> GIFFrames.Animation? {
        let cacheKey = "\(itemID.uuidString):\(byteSize):\(budget.maxPixel)" as NSString
        if let cached = animationCache.object(forKey: cacheKey) {
            return cached.animation
        }
        guard let container else { return nil }
        let service = await ThumbnailServices.shared.service(for: container)
        guard let thumbnail = await service.thumbnail(for: itemID, maxPixel: cardPixel), thumbnail.isAnimated else {
            return nil
        }
        guard let decoded = await GIFDecodeGate.shared.run({
            await GIFFrames.decode(thumbnail.data, budget: budget)
        }) else { return nil }
        animationCache.setObject(BoxedAnimation(decoded), forKey: cacheKey, cost: decoded.byteCost)
        return decoded
    }

    @concurrent
    static func linkMedia(for itemID: UUID) async -> (image: UIImage?, isAnimated: Bool) {
        guard let data = LinkPreviewImageStore().load(for: itemID) else { return (nil, false) }
        return await (decode(data), data.isGIF)
    }

    @MainActor
    static func linkGIFFrames(for itemID: UUID, budget: GIFFrames.Budget) async -> GIFFrames.Animation? {
        let cacheKey = "link:\(itemID.uuidString):\(budget.maxPixel)" as NSString
        if let cached = animationCache.object(forKey: cacheKey) {
            return cached.animation
        }
        guard let data = LinkPreviewImageStore().load(for: itemID), data.isGIF else { return nil }
        guard let decoded = await GIFDecodeGate.shared.run({
            await GIFFrames.decode(data, budget: budget)
        }) else { return nil }
        animationCache.setObject(BoxedAnimation(decoded), forKey: cacheKey, cost: decoded.byteCost)
        return decoded
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
    var accessibilityText: String?
    @Environment(MobileAppState.self) private var appState
    @State private var picture: CardMedia.Picture?

    var body: some View {
        Group {
            if let animation = picture?.animation, !Motion.reduceMotion {
                AnimatedPicture(animation: animation, fills: false)
                    .aspectRatio(picture.map { $0.image.size.width / max(1, $0.image.size.height) }, contentMode: .fit)
            } else if let image = picture?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.12)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .modifier(PictureAccessibility(text: accessibilityText))
        .task(id: "\(itemID.uuidString):\(byteSize)") {
            picture = await CardMedia.picture(
                itemID: itemID, byteSize: byteSize, container: appState.historyContainer, maxPixel: maxPixel,
                frames: Motion.reduceMotion ? nil : .detail
            )
        }
    }
}

private struct PictureAccessibility: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.accessibilityElement(children: .ignore).accessibilityLabel(text).accessibilityAddTraits(.isImage)
        } else {
            content.accessibilityHidden(true)
        }
    }
}
