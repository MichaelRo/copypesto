// SPDX-License-Identifier: MIT
import Foundation
import UIKit

/// The apps' icons a sealed set carries, decoded once per app for every card that shows them. A new icon for the same
/// app (the set was written again) replaces the old one.
@MainActor
enum AppIconImages {
    private final class Decoded {
        let data: Data
        let image: UIImage

        init(data: Data, image: UIImage) {
            self.data = data
            self.image = image
        }
    }

    private static let cache: NSCache<NSString, Decoded> = {
        let cache = NSCache<NSString, Decoded>()
        cache.countLimit = 64
        return cache
    }()

    static func image(for bundleID: String?, data: Data) -> UIImage? {
        guard let bundleID else { return nil }
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key), cached.data == data { return cached.image }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(Decoded(data: data, image: image), forKey: key)
        return image
    }
}
