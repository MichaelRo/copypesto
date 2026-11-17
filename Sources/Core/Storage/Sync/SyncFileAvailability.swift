// SPDX-License-Identifier: MIT
import Foundation

enum SyncFileAvailability {
    struct UbiquitousStatus {
        let isUbiquitousItem: Bool
        let downloadingStatus: URLUbiquitousItemDownloadingStatus?
    }

    static let datalessFlag = DatalessFile.flag

    static func defaultUbiquitousStatus(_ url: URL) -> UbiquitousStatus? {
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]) else { return nil }
        return UbiquitousStatus(
            isUbiquitousItem: values.isUbiquitousItem == true,
            downloadingStatus: values.ubiquitousItemDownloadingStatus
        )
    }

    /// False for a file a provider has listed but not downloaded yet; asking for it to be downloaded starts that, off
    /// this thread. A file in an ordinary folder is always readable.
    static func isReadable(
        _ url: URL,
        flags: (URL) -> UInt32? = DatalessFile.fileFlags,
        ubiquitousStatus: (URL) -> UbiquitousStatus? = defaultUbiquitousStatus,
        startUbiquitousDownload: (URL) -> Void = { try? FileManager.default.startDownloadingUbiquitousItem(at: $0) }
    )
        -> Bool
    {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        if DatalessFile.isDataless(url, flags: flags) {
            DatalessFile.fetchInBackground(url)
            return false
        }
        guard let values = ubiquitousStatus(url), values.isUbiquitousItem else { return true }
        if values.downloadingStatus == .current || values.downloadingStatus == .downloaded {
            return true
        }
        startUbiquitousDownload(url)
        return false
    }
}
