// SPDX-License-Identifier: MIT
import Foundation

enum SyncFileAvailability {
    /// False for a file iCloud Drive has listed but not downloaded yet; asking for it to be downloaded starts that. A
    /// file in an ordinary folder is always readable.
    static func isReadable(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]),
            values.isUbiquitousItem == true else { return true }
        if values.ubiquitousItemDownloadingStatus == .current || values.ubiquitousItemDownloadingStatus == .downloaded {
            return true
        }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return false
    }
}
