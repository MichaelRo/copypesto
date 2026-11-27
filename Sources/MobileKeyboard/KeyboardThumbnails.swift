// SPDX-License-Identifier: MIT
import Foundation
import UIKit

/// The keyboard's pictures, decoded once and ready to draw, with the blurred ground a picture that does not fill its
/// card sits on rendered once beside it. Scrolling the row back used to decode each picture again and blur it live.
@MainActor
final class KeyboardThumbnails {
    final class Picture: @unchecked Sendable {
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
    nonisolated static let backdropPixels: CGFloat = 10

    private let cache: NSCache<NSUUID, Picture> = {
        let cache = NSCache<NSUUID, Picture>()
        cache.totalCostLimit = costLimit
        return cache
    }()

    func cachedPicture(for id: UUID) -> Picture? {
        cache.object(forKey: id as NSUUID)
    }

    func picture(for id: UUID, data: Data) -> Picture? {
        if let cached = cachedPicture(for: id) { return cached }
        guard let picture = Self.decodePicture(data: data) else { return nil }
        cache.setObject(picture, forKey: id as NSUUID, cost: Self.cost(of: picture.image))
        return picture
    }

    func loadPicture(for id: UUID, data: Data) async -> Picture? {
        if let cached = cachedPicture(for: id) { return cached }
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decodePicture(data: data)
        }.value
        guard let decoded else { return nil }
        if let existing = cachedPicture(for: id) { return existing }
        cache.setObject(decoded, forKey: id as NSUUID, cost: Self.cost(of: decoded.image))
        return decoded
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private nonisolated static func decodePicture(data: Data) -> Picture? {
        guard let decoded = UIImage(data: data) else { return nil }
        let image = decoded.preparingForDisplay() ?? decoded
        return Picture(image: image, backdrop: backdrop(of: image))
    }

    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    private nonisolated static func backdrop(of image: UIImage) -> UIImage? {
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
