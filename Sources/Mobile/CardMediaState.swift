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
    private(set) var revealedText: String?

    init(picture: CardMedia.Picture? = nil, linkPicture: UIImage? = nil) {
        self.picture = picture
        self.linkPicture = linkPicture
    }

    struct Key: Hashable {
        let id: UUID
        let isShown: Bool
    }

    func load(
        _ item: ClipboardItem, container: ModelContainer?, isShown: Bool, fetchPreview: () async -> Bool = { false }
    ) async {
        revealedText = isShown ? HiddenClipReveal.readableText(from: item.blob?.decryptedData()) : nil
        switch item.type {
        case .image where item.sensitivityRaw == nil:
            guard picture == nil else { return }
            picture = await CardMedia.picture(
                itemID: item.id, byteSize: item.byteSize, container: container, maxPixel: CardMedia.cardPixel
            )
        case .url where item.sensitivityRaw == nil:
            if linkPicture == nil { linkPicture = await CardMedia.linkPicture(for: item.id) }
            if await fetchPreview(), linkPicture == nil { linkPicture = await CardMedia.linkPicture(for: item.id) }
        default:
            break
        }
    }

    /// Plays a GIF only for a card that stayed on screen (`GIFPlayback.settleDelay`): a card scrolled past while the
    /// grid moves decodes nothing. Cancelled with the card's task, it decodes nothing at all.
    func animate(
        settleDelay: Duration = GIFPlayback.settleDelay,
        decode: () async -> GIFFrames.Animation?
    ) async {
        guard picture?.isAnimated == true, picture?.animation == nil else { return }
        try? await Task.sleep(for: settleDelay)
        guard !Task.isCancelled, let animation = await decode(), !Task.isCancelled else { return }
        picture?.animation = animation
    }

    /// The card left the screen: its frames (up to 12 MB) go, the still stays.
    func dropAnimation() {
        picture?.animation = nil
    }
}
