// SPDX-License-Identifier: MIT
import AppKit

/// Card pictures already made, kept in memory. A card that scrolls out of the row and back in is built again, and
/// without this each return decrypted the whole picture, shrank it and decoded the result again, which is what made a
/// shelf of screenshots heavy to scroll. Cleared when the history locks or is cleared, like the decrypted previews.
@MainActor
public final class ThumbnailCache {
    public static let shared = ThumbnailCache()

    public struct Entry {
        public let image: NSImage
        public let isAnimated: Bool
        /// The clip's size when the picture was made. A still that becomes its GIF changes the size, so the cached
        /// still
        /// is not offered for it.
        public let byteSize: Int

        public init(image: NSImage, isAnimated: Bool, byteSize: Int) {
            self.image = image
            self.isAnimated = isAnimated
            self.byteSize = byteSize
        }
    }

    private final class Box {
        let entry: Entry
        init(_ entry: Entry) {
            self.entry = entry
        }
    }

    private let storage = NSCache<NSUUID, Box>()

    public init(byteLimit: Int = 48 * 1024 * 1024, countLimit: Int = 600) {
        storage.totalCostLimit = byteLimit
        storage.countLimit = countLimit
    }

    public func entry(for id: UUID, byteSize: Int) -> Entry? {
        storage.object(forKey: id as NSUUID)?.entry.matching(byteSize: byteSize)
    }

    public func store(_ entry: Entry, for id: UUID) {
        let cost = max(1, Int(entry.image.size.width * entry.image.size.height * 4))
        storage.setObject(Box(entry), forKey: id as NSUUID, cost: cost)
    }

    public func clear() {
        storage.removeAllObjects()
    }
}

private extension ThumbnailCache.Entry {
    func matching(byteSize: Int) -> ThumbnailCache.Entry? {
        self.byteSize == byteSize ? self : nil
    }
}
