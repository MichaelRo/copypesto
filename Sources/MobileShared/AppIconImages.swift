// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import UIKit

/// The apps' icons a sealed set carries, decoded once per app and icon for every card that shows them.
@MainActor
enum AppIconImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        return cache
    }()

    static func image(for bundleID: String?, data: Data) -> UIImage? {
        guard let bundleID else { return nil }
        // The icon's digest is part of the key: an app's new icon must not hit its old one.
        let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        let key = "\(bundleID)#\(digest)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
