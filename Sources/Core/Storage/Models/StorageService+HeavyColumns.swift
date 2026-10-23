// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public extension StorageService {
    /// Link preview images used to be a plaintext column on every item (about 37 MB per 5,000 items in memory); they
    /// live in the encrypted `LinkPreviewImageStore` now. An image is removed from the row only once its file is
    /// written.
    @discardableResult
    func moveLinkPreviewImages() async throws -> Int {
        var moved = 0
        try await forEachClip(matching: FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.ogImageThumbnail != nil }
        )) { item in
            guard let image = item.ogImageThumbnail,
                  (try? linkPreviews.save(image, for: item.id)) != nil else { return }
            item.ogImageThumbnail = nil
            moved += 1
        }
        return moved
    }

    /// Icons were once copied onto every item (5,000 items cost about 25 MB); they resolve by bundle ID now.
    @discardableResult
    func clearLegacyIcons() async throws -> Int {
        var cleared = 0
        try await forEachClip(matching: FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.sourceIconData != nil }
        )) { item in
            item.sourceIconData = nil
            cleared += 1
        }
        return cleared
    }
}
