// SPDX-License-Identifier: MIT
import Darwin
import Foundation

/// The one way a file the person did not write is read for an import: opened without blocking, checked on the open
/// descriptor to be a regular file, sized before any of it is read, and read no further than the limit.
enum CollectionFileReader {
    static func read(_ url: URL, maxBytes: Int) throws -> Data {
        let descriptor = open(url.resolvingSymlinksInPath().path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw HistoryExporter.ImportError.notARegularFile
        }
        guard info.st_size <= maxBytes else { throw HistoryExporter.ImportError.fileTooLarge }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw HistoryExporter.ImportError.fileTooLarge }
        return data
    }
}
