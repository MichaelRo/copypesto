// SPDX-License-Identifier: MIT
import CoreImage
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
    private static let backdropPixels: CGFloat = 48

    private let cache: NSCache<NSUUID, Picture> = {
        let cache = NSCache<NSUUID, Picture>()
        cache.totalCostLimit = costLimit
        return cache
    }()

    private let context = CIContext(options: [.useSoftwareRenderer: false])

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

    /// A small, heavily blurred copy: it is stretched to fill the card, so a few dozen pixels are enough.
    private func backdrop(of image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let longest = max(CGFloat(cgImage.width), CGFloat(cgImage.height))
        let scale = min(1, Self.backdropPixels / max(longest, 1))
        let input = CIImage(cgImage: cgImage)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = input.extent
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: 4)
            .cropped(to: extent)
        guard let output = context.createCGImage(blurred, from: extent) else { return nil }
        return UIImage(cgImage: output)
    }
}
