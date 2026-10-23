// SPDX-License-Identifier: MIT
import Foundation
import os

/// Persists the most-recent non-sensitive clipboard item as a small JSON file.
///
/// Written by `StorageService` at every ingest; read by the `pesto` CLI tool and the
/// `get last item` AppleScript command. Both sides agree on the path via bundle ID.
/// Writes are atomic so readers never see a torn file.
public enum LastItemStore {
    public struct Item: Codable, Sendable {
        /// Nil in a file written before ids were recorded.
        public let id: UUID?
        public let preview: String
        public let type: String
        public let timestamp: Date
        public let sourceApp: String?
    }

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "LastItemStore")

    #if DEBUG
        /// Override point for tests: swapped to a temp-dir URL in test suites. It does not exist in a Release build, so
        /// nothing shipped can redirect where the last-item file is written.
        nonisolated(unsafe) static var testFileURL: URL?

        static var fileURL: URL {
            testFileURL ?? AppPaths.supportDirectory.appendingPathComponent("last-item.json")
        }
    #else
        static var fileURL: URL {
            AppPaths.supportDirectory.appendingPathComponent("last-item.json")
        }
    #endif

    /// Atomically writes item metadata to the shared last-item file.
    /// Never throws — the write is best-effort; a failed write does not affect core function.
    public static func write(id: UUID? = nil, preview: String, type: String, timestamp: Date, sourceApp: String?) {
        let item = Item(id: id, preview: preview, type: type, timestamp: timestamp, sourceApp: sourceApp)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(item) else { return }
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Owner-only from creation: the file contains preview text of clipboard items.
        do {
            try PrivateFile.write(data, to: url)
        } catch {
            logger.error("last-item write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes the file. It holds clipboard text outside the encrypted store, so it must not outlive a
    /// delete or a clear.
    public static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Removes the file only if it describes this item.
    public static func clear(ifItemID id: UUID) {
        guard read()?.id == id else { return }
        clear()
    }

    /// For the command-line tool, which cannot ask for Touch ID: with the History Lock on it reads nothing.
    public static func read(lockIsOn: Bool) -> Item? {
        lockIsOn ? nil : read()
    }

    /// Returns the most recent item, or `nil` if the file does not exist or cannot be decoded.
    public static func read() -> Item? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Item.self, from: data)
    }
}

/// What `StorageService` needs from the last-item file, so tests can observe it without sharing a global file.
public protocol LastItemStoring: Sendable {
    func write(id: UUID, preview: String, type: String, timestamp: Date, sourceApp: String?)
    func clear()
    func clear(ifItemID id: UUID)
}

public struct FileLastItemStore: LastItemStoring {
    public init() {}

    public func write(id: UUID, preview: String, type: String, timestamp: Date, sourceApp: String?) {
        LastItemStore.write(id: id, preview: preview, type: type, timestamp: timestamp, sourceApp: sourceApp)
    }

    public func clear() {
        LastItemStore.clear()
    }

    public func clear(ifItemID id: UUID) {
        LastItemStore.clear(ifItemID: id)
    }
}

/// A test host writes no last-item file unless a test injects a store: the file is one global, and a clip judged in the
/// background can be saved after the test that copied it has moved on.
public struct NoLastItemFile: LastItemStoring {
    public init() {}

    public func write(id _: UUID, preview _: String, type _: String, timestamp _: Date, sourceApp _: String?) {}
    public func clear() {}
    public func clear(ifItemID _: UUID) {}
}
