// SPDX-License-Identifier: MIT
import Foundation

enum SyncFileAvailability {
    /// `SF_DATALESS` from `<sys/stat.h>`: the file's name and size are here, its bytes are in the cloud. Dropbox and
    /// Google Drive (File Provider folders) show files like this, and reading one makes the system fetch it, which
    /// can take as long as the connection does and can fail offline.
    static let datalessFlag: UInt32 = 0x4000_0000

    /// False for a file a provider has listed but not downloaded yet; asking for it to be downloaded starts that, off
    /// this thread. A file in an ordinary folder is always readable.
    static func isReadable(_ url: URL, flags: (URL) -> UInt32? = fileFlags) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        if let flags = flags(url), flags & datalessFlag != 0 {
            Task.detached(priority: .utility) {
                if let handle = try? FileHandle(forReadingFrom: url) {
                    _ = try? handle.read(upToCount: 1)
                    try? handle.close()
                }
            }
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

    private static func fileFlags(_ url: URL) -> UInt32? {
        var info = stat()
        return stat(url.path, &info) == 0 ? info.st_flags : nil
    }
}
