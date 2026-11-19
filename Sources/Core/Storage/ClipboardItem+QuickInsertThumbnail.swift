// SPDX-License-Identifier: MIT
import Foundation

public extension ClipboardItem {
    /// Downsampled JPEG thumbnail for the quick-insert set, kept under `QuickInsertPolicy.maxThumbnailBytes`.
    func quickInsertThumbnailData() -> Data? {
        guard type == .image else { return nil }
        return blob?.decryptedData().flatMap {
            ImageDownsampler.thumbnailJPEG(
                from: $0, maxPixel: QuickInsertPolicy.thumbnailMaxPixel,
                maxBytes: QuickInsertPolicy.maxThumbnailBytes
            )
        }
    }
}
