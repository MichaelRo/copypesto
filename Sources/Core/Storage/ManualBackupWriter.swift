// SPDX-License-Identifier: MIT
import Foundation
import SwiftData

public enum ManualBackupError: Error, Equatable, Sendable {
    /// The history is only in memory, so a backup of it would hold nothing worth keeping.
    case storeNotOnDisk
}

/// Writes one backup file the person asked for (iPhone and iPad, ADR 0078). Unlike `AutoBackupService` it replaces
/// nothing, so there is no guard against a shrinking history: the file is new and the person picks where it goes.
/// It is streamed to `<url>.partial` and moved to `url` only once the manifest is written; a failure leaves neither.
public struct ManualBackupWriter: Sendable {
    public struct Result: Sendable, Equatable {
        public let bytes: Int
        public let summary: BackupExportSummary
    }

    private let container: ModelContainer
    private let storeIsOnDisk: Bool

    public init(container: ModelContainer, storeIsOnDisk: Bool) {
        self.container = container
        self.storeIsOnDisk = storeIsOnDisk
    }

    public func write(
        to url: URL, key: BackupKey, header: Data, includeSensitive: Bool, origin: BackupOrigin
    ) async throws
    -> Result {
        guard storeIsOnDisk else { throw ManualBackupError.storeNotOnDisk }
        let manager = FileManager.default
        let partial = url.appendingPathExtension("partial")
        try? manager.removeItem(at: partial)
        let writer = try BackupFile.StreamingWriter(url: partial, key: key, header: header)
        do {
            let summary = try await StorageService(modelContainer: container).streamBackupRecords(
                includeSensitive: includeSensitive, sink: { try writer.append($0) }
            )
            let bytes = try writer.finish(origin: origin)
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: partial)
            } else {
                try manager.moveItem(at: partial, to: url)
            }
            return Result(bytes: bytes, summary: summary)
        } catch {
            writer.abandon()
            try? manager.removeItem(at: partial)
            throw error
        }
    }
}
