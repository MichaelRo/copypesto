// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore
import SwiftData
import UIKit

/// What a card loads after it appears: its picture, a link's preview picture, or a shown secret's text. Each is loaded
/// only for a card on screen, and a shown secret's text is dropped as soon as it hides again.
@MainActor
@Observable
final class CardMediaState {
    private(set) var picture: CardMedia.Picture?
    private(set) var linkPicture: UIImage?
    private(set) var linkAnimation: GIFFrames.Animation?
    private(set) var linkIsAnimated = false
    private(set) var revealedText: String?
    private var loadedByteSize: Int?

    var isAnimated: Bool {
        picture?.isAnimated == true
    }

    var isLinkAnimated: Bool {
        linkIsAnimated
    }

    init(picture: CardMedia.Picture? = nil, linkPicture: UIImage? = nil) {
        self.picture = picture
        self.linkPicture = linkPicture
    }

    struct Key: Hashable {
        let id: UUID
        let isShown: Bool
        var byteSize: Int = 0
        var isAnimatedHint: Bool = false
    }

    func load(
        _ item: ClipboardItem, container: ModelContainer?, isShown: Bool, fetchPreview: () async -> Bool = { false }
    ) async {
        revealedText = isShown ? HiddenClipReveal.readableText(from: item.blob?.decryptedData()) : nil
        switch item.type {
        case .image where item.sensitivityRaw == nil:
            guard picture == nil || loadedByteSize != item.byteSize else { return }
            picture = await CardMedia.picture(
                itemID: item.id, byteSize: item.byteSize, container: container, maxPixel: CardMedia.cardPixel
            )
            loadedByteSize = item.byteSize
        case .url where item.sensitivityRaw == nil:
            if linkPicture == nil {
                let loaded = await CardMedia.linkMedia(for: item.id)
                linkPicture = loaded.image
                linkIsAnimated = loaded.isAnimated
            }
            if await fetchPreview(), linkPicture == nil {
                let loaded = await CardMedia.linkMedia(for: item.id)
                linkPicture = loaded.image
                linkIsAnimated = loaded.isAnimated
            }
        default:
            break
        }
    }

    func load(
        for key: Key,
        picture loadPicture: () async -> CardMedia.Picture?,
        linkPreview loadLinkPreview: () async -> (image: UIImage?, isAnimated: Bool)? = { nil }
    ) async {
        if picture == nil || loadedByteSize != key.byteSize {
            if let loaded = await loadPicture(), !Task.isCancelled {
                picture = loaded
                loadedByteSize = key.byteSize
            }
        }
        if linkPicture == nil, let loadedLink = await loadLinkPreview(), !Task.isCancelled {
            linkPicture = loadedLink.image
            linkIsAnimated = loadedLink.isAnimated
        }
    }

    /// Plays a GIF only for a card that stayed on screen (`GIFPlayback.settleDelay`): a card scrolled past while the
    /// grid moves decodes nothing. Cancelled with the card's task, it decodes nothing at all.
    func animate(
        settleDelay: Duration = GIFPlayback.settleDelay,
        decode: () async -> GIFFrames.Animation?,
        linkDecode: (() async -> GIFFrames.Animation?)? = nil
    ) async {
        let needsPicture = picture?.isAnimated == true && picture?.animation == nil
        let needsLink = linkIsAnimated && linkAnimation == nil
        guard needsPicture || needsLink else { return }
        try? await Task.sleep(for: settleDelay)
        guard !Task.isCancelled else { return }
        if needsPicture, let animation = await decode(), !Task.isCancelled {
            picture?.animation = animation
        }
        if needsLink, let animation = await linkDecode?(), !Task.isCancelled {
            linkAnimation = animation
        }
    }

    /// The card left the screen: its frames (up to 12 MB) go, the still stays.
    func dropAnimation() {
        picture?.animation = nil
        linkAnimation = nil
    }
}
