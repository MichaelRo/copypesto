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

    struct Key: Hashable {
        let id: UUID
        let isShown: Bool
    }

    func load(_ item: ClipboardItem, container: ModelContainer?, isShown: Bool) async {
        revealedText = isShown ? HiddenClipReveal.readableText(from: item.blob?.decryptedData()) : nil
        switch item.type {
        case .image where item.sensitivityRaw == nil:
            guard picture == nil else { return }
            picture = await CardMedia.picture(
                itemID: item.id, byteSize: item.byteSize, container: container, maxPixel: CardMedia.cardPixel
            )
        case .url where item.sensitivityRaw == nil:
            guard linkPicture == nil else { return }
            linkPicture = await CardMedia.linkPicture(for: item.id)
        default:
            break
        }
    }
}
