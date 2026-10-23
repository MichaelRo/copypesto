// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// What a reader found in another clipboard app's library: the clips, and how many entries it could not use (pictures
/// and anything that is not text, items with no content).
public struct ClipboardAppLibrary: Sendable {
    public let records: [PasteImportRecord]
    public let skipped: Int

    public init(records: [PasteImportRecord], skipped: Int) {
        self.records = records
        self.skipped = skipped
    }
}

/// Shared by the readers of other clipboard apps' SQLite libraries (ADR 0011). Like the Paste reader, they work on a
/// copy, open it read-only, bound what they read, and write nowhere but a temporary folder they remove afterwards, so a
/// running app is never disturbed and its library is never opened for writing. Both layouts come from the apps' own
/// data models and are checked for before they are read: a file that does not look like theirs is `notRecognized`.
public enum ClipboardAppLibraryReader {
    public enum ReadError: Error, Equatable {
        case notFound
        case tooLarge
        case notRecognized
        case unreadable
    }

    public static let maxDatabaseBytes = 1_000_000_000
    public static let maxRecords = 20_000
    public static let maxValueBytes = 50_000_000

    static func withCopy<Result>(
        of url: URL, named name: String, fileManager: FileManager = .default,
        _ body: (OpaquePointer) throws -> Result
    )
    throws -> Result {
        guard fileManager.fileExists(atPath: url.path) else { throw ReadError.notFound }
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int else {
            throw ReadError.unreadable
        }
        guard size <= maxDatabaseBytes else { throw ReadError.tooLarge }
        let folder = fileManager.temporaryDirectory.appendingPathComponent("pesto-import-\(UUID().uuidString)")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: folder) }
        let copy = folder.appendingPathComponent(name)
        do {
            try fileManager.copyItem(at: url, to: copy)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: url.path + suffix)
                if fileManager.fileExists(atPath: sidecar.path) {
                    try fileManager.copyItem(at: sidecar, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
        } catch {
            throw ReadError.unreadable
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw ReadError.unreadable
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    static func hasTables(_ db: OpaquePointer, _ names: [String]) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table'", -1, &statement, nil)
            == SQLITE_OK, let rows = statement else { return false }
        defer { sqlite3_finalize(rows) }
        var found = Set<String>()
        while sqlite3_step(rows) == SQLITE_ROW {
            if let text = text(rows, 0) { found.insert(text) }
        }
        return names.allSatisfy(found.contains)
    }

    static func prepare(_ db: OpaquePointer, _ query: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let rows = statement else {
            throw ReadError.notRecognized
        }
        return rows
    }

    static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}
