// SPDX-License-Identifier: MIT
import Foundation

/// A file in a sync folder that is small by nature (a vault, a device record, an identity, a grant, a join request) is
/// read through this, so a huge file that someone put in the shared folder is refused before it is read, instead of
/// being loaded whole.
enum SyncSmallFile {
    static let maxBytes = 1 << 20

    /// Nil for a file a provider has listed but not downloaded: reading it would wait for the network, on whichever
    /// thread asked. It is fetched in the background and found on a later pass.
    static func read(_ url: URL, flags: (URL) -> UInt32? = DatalessFile.fileFlags) -> Data? {
        if DatalessFile.isDataless(url, flags: flags) {
            DatalessFile.fetchInBackground(url)
            return nil
        }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes + 1), data.count <= maxBytes else { return nil }
        return data
    }
}
