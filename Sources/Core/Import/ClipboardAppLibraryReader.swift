// SPDX-License-Identifier: MIT
#if os(macOS)
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
    static let inlineMarker: UInt8 = 0x01

    static func withCopy<Result>(
        of url: URL, named name: String, fileManager: FileManager = .default,
        _ body: (OpaquePointer) throws -> Result
    )
    throws -> Result {
        try withCopy(of: url, named: name, fileManager: fileManager) { db, _ in
            try body(db)
        }
    }

    static func withCopy<Result>(
        of url: URL, named name: String, fileManager: FileManager = .default,
        _ body: (OpaquePointer, URL) throws -> Result
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
        return try body(db, PasteExternalPayload.folder(besideDatabaseAt: url))
    }

    static func tableNames(in db: OpaquePointer) -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table'", -1, &statement, nil)
            == SQLITE_OK, let rows = statement else { return [] }
        defer { sqlite3_finalize(rows) }
        var found = Set<String>()
        while sqlite3_step(rows) == SQLITE_ROW {
            if let text = text(rows, 0) { found.insert(text) }
        }
        return found
    }

    static func hasTables(_ db: OpaquePointer, _ names: [String]) -> Bool {
        let found = tableNames(in: db)
        return names.allSatisfy(found.contains)
    }

    static func columnNames(of table: String, in db: OpaquePointer) -> Set<String> {
        guard table.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return []
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(table)\")", -1, &statement, nil) == SQLITE_OK,
              let rows = statement else { return [] }
        defer { sqlite3_finalize(rows) }
        var columns = Set<String>()
        while sqlite3_step(rows) == SQLITE_ROW {
            if let name = text(rows, 1) { columns.insert(name) }
        }
        return columns
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

    static func blob(
        _ statement: OpaquePointer,
        _ column: Int32,
        externalFolder: URL? = nil,
        unwrapsInlineMarker: Bool = true,
        limit: Int = maxValueBytes
    )
    -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0 else { return nil }
        let firstByte = bytes.load(as: UInt8.self)
        if count < 64, firstByte == PasteExternalPayload.externalMarker {
            let value = Data(bytes: bytes, count: count)
            if let fileName = PasteExternalPayload.fileName(in: value) {
                return PasteExternalPayload.read(fileName, in: externalFolder, limit: limit)
            }
            if value.dropFirst().contains(0) { return nil }
        }
        if unwrapsInlineMarker, firstByte == inlineMarker {
            guard count > 1, count - 1 <= limit else { return nil }
            return Data(bytes: bytes.advanced(by: 1), count: count - 1)
        }
        guard count <= limit else { return nil }
        return Data(bytes: bytes, count: count)
    }

    static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    static func readExternalFile(named fileName: String, in folder: URL, limit: Int = maxValueBytes) -> Data? {
        readContainedFile(relativeComponents: [fileName], inside: folder, limit: limit)
    }

    static func readContainedFile(
        relativeComponents: [String],
        inside rootFolder: URL,
        limit: Int = maxValueBytes
    )
    -> Data? {
        guard !relativeComponents.isEmpty, relativeComponents.allSatisfy(isPlainFileName) else { return nil }
        var dirFD = Darwin.open(rootFolder.path, O_RDONLY | O_DIRECTORY)
        guard dirFD >= 0 else { return nil }
        for component in relativeComponents.dropLast() {
            let nextFD = Darwin.openat(dirFD, component, O_RDONLY | O_NOFOLLOW | O_DIRECTORY)
            close(dirFD)
            guard nextFD >= 0 else { return nil }
            dirFD = nextFD
        }
        guard let last = relativeComponents.last else {
            close(dirFD)
            return nil
        }
        let fileFD = Darwin.openat(dirFD, last, O_RDONLY | O_NOFOLLOW)
        close(dirFD)
        guard fileFD >= 0 else { return nil }
        var info = stat()
        guard fstat(fileFD, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0,
              Int(info.st_size) <= limit else
        {
            close(fileFD)
            return nil
        }
        let handle = FileHandle(fileDescriptor: fileFD, closeOnDealloc: true)
        guard let data = try? handle.read(upToCount: limit + 1), !data.isEmpty, data.count <= limit else {
            return nil
        }
        return data
    }

    static func imageUTI(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "tiff", "tif": "public.tiff"
        case "png": "public.png"
        case "jpg", "jpeg": "public.jpeg"
        case "gif": "com.compuserve.gif"
        case "heic": "public.heic"
        case "webp": "public.webp"
        default: nil
        }
    }

    static func imageUTI(forBytes data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "public.png" }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "public.jpeg" }
        if head.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "com.compuserve.gif" }
        if head.starts(with: [0x49, 0x49, 0x2A, 0x00]) || head.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "public.tiff"
        }
        if head.count >= 12,
           head[0...3] == [0x52, 0x49, 0x46, 0x46],
           head[8...11] == [0x57, 0x45, 0x42, 0x50]
        {
            return "public.webp"
        }
        if head.count >= 12,
           head[4...7] == [0x66, 0x74, 0x79, 0x70],
           let brand = String(bytes: head[8...11], encoding: .ascii),
           brand.hasPrefix("hei") || brand == "mif1"
        {
            return "public.heic"
        }
        return nil
    }

    static func date(from rawTime: Double) -> Date {
        rawTime > 1_000_000_000
            ? Date(timeIntervalSince1970: rawTime)
            : (rawTime > 0 ? Date(timeIntervalSinceReferenceDate: rawTime) : .now)
    }
}
#endif
