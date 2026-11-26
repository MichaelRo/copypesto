// SPDX-License-Identifier: MIT
import Foundation
import UIKit

/// The keyboard's pictures, decoded once and ready to draw, with the blurred ground a picture that does not fill its
/// card sits on rendered once beside it. Scrolling the row back used to decode each picture again and blur it live.
@MainActor
final class KeyboardThumbnails {
    final class Picture {
        let image: UIImage
        let backdrop: UIImage?

        init(image: UIImage, backdrop: UIImage?) {
            self.image = image
            self.backdrop = backdrop
        }
    }

    static let shared = KeyboardThumbnails()

    /// About 60 decoded 240-pixel thumbnails, far below a keyboard extension's memory limit.
    private static let costLimit = 16 * 1024 * 1024
    /// The backdrop's longer side: stretched over the card with smooth interpolation, a picture this small reads as
    /// its own blur, with no Core Image (and no GPU work) in the keyboard.
    static let backdropPixels: CGFloat = 10

    private let cache: NSCache<NSUUID, Picture> = {
        let cache = NSCache<NSUUID, Picture>()
        cache.totalCostLimit = costLimit
        return cache
    }()

    func picture(for id: UUID, data: Data) -> Picture? {
        let key = id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let decoded = UIImage(data: data) else { return nil }
        let image = decoded.preparingForDisplay() ?? decoded
        let picture = Picture(image: image, backdrop: backdrop(of: image))
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        cache.setObject(picture, forKey: key, cost: cost)
        return picture
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func backdrop(of image: UIImage) -> UIImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, Self.backdropPixels / longest)
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
