// SPDX-License-Identifier: MIT
import Foundation

enum SyncFileAvailability {
    static let datalessFlag = DatalessFile.flag

    /// False for a file a provider has listed but not downloaded yet; asking for it to be downloaded starts that, off
    /// this thread. A file in an ordinary folder is always readable.
    static func isReadable(_ url: URL, flags: (URL) -> UInt32? = DatalessFile.fileFlags) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        if DatalessFile.isDataless(url, flags: flags) {
            DatalessFile.fetchInBackground(url)
            return false
        }
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
