// SPDX-License-Identifier: MIT
import Darwin
import Foundation

/// Writes a file that is owner-only from the moment it exists. `Data.write(.atomic)` followed by a `chmod` leaves a
/// window in which the renamed file has the umask's mode (normally 0644), and every replacement reopens it.
public enum PrivateFile {
    struct Temporary {
        let descriptor: Int32
        let url: URL
    }

    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = try createTemporary(in: directory)
        do {
            defer { close(temporary.descriptor) }
            try write(data, to: temporary.descriptor)
            guard fsync(temporary.descriptor) == 0 else { throw posixError() }
        } catch {
            try? FileManager.default.removeItem(at: temporary.url)
            throw error
        }
        guard rename(temporary.url.path, url.path) == 0 else {
            let error = posixError()
            try? FileManager.default.removeItem(at: temporary.url)
            throw error
        }
    }

    static func createTemporary(in directory: URL) throws -> Temporary {
        let url = directory.appendingPathComponent(".pesto-\(UUID().uuidString).tmp")
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        return Temporary(descriptor: descriptor, url: url)
    }

    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                offset += written
            }
        }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
