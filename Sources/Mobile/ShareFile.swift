// SPDX-License-Identifier: MIT
import Foundation

/// A clip written to a file in the temporary folder for the system share sheet, which shares a file by what it is
/// (a GIF stays animated). Each file has a folder of its own so it keeps a plain name; folders older than
/// `lifetime` are removed whenever another is written.
enum ShareFile {
    static let lifetime: TimeInterval = 3600
    static let folderName = "pesto-share"

    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    static func write(
        _ data: Data, fileName: String = "Pesto", fileExtension: String, in root: URL = directory, now: Date = .now
    ) throws
    -> URL {
        let file = try reserve(fileName: fileName, fileExtension: fileExtension, in: root, now: now)
        try data.write(to: file, options: .completeFileProtection)
        return file
    }

    /// Where a file of that name may be written, in a folder of its own that the same sweeps remove; nothing is
    /// written yet. For a file streamed to disk rather than held in memory (a backup).
    static func reserve(
        fileName: String, fileExtension: String, in root: URL = directory, now: Date = .now
    ) throws
    -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        sweep(in: root, now: now)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let cleanName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let stem = cleanName.isEmpty ? "Pesto" : cleanName
        return folder.appendingPathComponent("\(stem).\(fileExtension)")
    }

    /// A shared file is plaintext, so it goes as soon as the share sheet is done with it, and with the lock, a clear,
    /// leaving the app and the next launch.
    static func owns(_ file: URL, in root: URL = directory) -> Bool {
        file.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
    }

    static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    static func removeAll(in root: URL = directory) {
        try? FileManager.default.removeItem(at: root)
    }

    static func sweep(in root: URL = directory, now: Date = .now) {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if now.timeIntervalSince(created) > lifetime { try? manager.removeItem(at: folder) }
        }
    }
}
