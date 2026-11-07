// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// `SF_DATALESS` from `<sys/stat.h>`: the file's name and size are here, its bytes are in the cloud. Dropbox and
/// Google Drive (File Provider folders) show files like this, and reading one makes the system fetch it, which can
/// take as long as the connection does and can fail offline.
enum DatalessFile {
    static let flag: UInt32 = 0x4000_0000

    static func isDataless(_ url: URL, flags: (URL) -> UInt32? = fileFlags) -> Bool {
        guard let value = flags(url) else { return false }
        return value & flag != 0
    }

    private static let fetching = Mutex<Set<String>>([])

    /// Asks the system for the file's bytes off the calling thread, once at a time per file.
    static func fetchInBackground(_ url: URL) {
        let started = fetching.withLock { $0.insert(url.path).inserted }
        guard started else { return }
        Task.detached(priority: .utility) {
            if let handle = try? FileHandle(forReadingFrom: url) {
                _ = try? handle.read(upToCount: 1)
                try? handle.close()
            }
            _ = fetching.withLock { $0.remove(url.path) }
        }
    }

    static func fileFlags(_ url: URL) -> UInt32? {
        var info = stat()
        return stat(url.path, &info) == 0 ? info.st_flags : nil
    }
}
