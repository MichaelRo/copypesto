// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

public struct PasteLibrary: Sendable {
    public struct Pinboard: Sendable {
        public let name: String
        public let records: [PasteImportRecord]
    }

    public let pinboards: [Pinboard]
    public let history: [PasteImportRecord]

    public var pinboardClipCount: Int {
        pinboards.reduce(0) { $0 + $1.records.count }
    }

    public var pinboardSummary: String {
        pinboards.map { "\($0.name) (\($0.records.count))" }.joined(separator: ", ")
    }

    public func records(includingHistory: Bool) -> [PasteImportRecord] {
        pinboards.flatMap(\.records) + (includingHistory ? history : [])
    }
}

/// Reads the Paste app's local Core Data mirror (`Paste.db`) into `PasteImportRecord`s. It works on a copy, so a
/// running Paste is never disturbed and the original is never opened for writing; it never writes anywhere but a
/// temporary folder it removes afterwards. See
/// `decisions/0011-read-only-surfaces.md`.
public enum PasteLibraryReader {
    public enum ReadError: Error, Equatable {
        case notFound
        case tooLarge
        case notAPasteLibrary
        case unreadable
    }

    public static let maxDatabaseBytes = 1_000_000_000
    public static let maxRecords = 20_000
    public static let maxRecordBytes = 50_000_000

    public static var defaultLocation: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.wiheads.paste", isDirectory: true)
    }

    public static var defaultDatabaseURL: URL {
        defaultLocation.appendingPathComponent("Paste.db")
    }

    public static func candidateDatabaseURLs(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    )
    -> [URL] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent("Application Support/com.wiheads.paste/Paste.db"),
            library.appendingPathComponent("Group Containers/group.com.wiheads.paste/Paste.db"),
            library.appendingPathComponent(
                "Containers/com.wiheads.paste/Data/Library/Application Support/Paste/Paste.db"
            ),
            library.appendingPathComponent(
                "Containers/com.wiheads.paste-setapp/Data/Library/Application Support/Paste/Paste.db"
            ),
            library.appendingPathComponent("Application Support/com.wiheads.paste-setapp/Paste.db")
        ]
    }

    public static func existingDatabaseURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    )
    -> URL? {
        candidateDatabaseURLs(homeDirectory: homeDirectory).first { fileManager.fileExists(atPath: $0.path) }
    }

    public static func read(databaseAt url: URL, fileManager: FileManager = .default) throws -> PasteLibrary {
        guard fileManager.fileExists(atPath: url.path) else { throw ReadError.notFound }
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int else {
            throw ReadError.unreadable
        }
        guard size <= maxDatabaseBytes else { throw ReadError.tooLarge }

        let workFolder = fileManager.temporaryDirectory.appendingPathComponent("pesto-paste-\(UUID().uuidString)")
        try fileManager.createDirectory(at: workFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workFolder) }
        let copy = workFolder.appendingPathComponent("Paste.db")
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
        return try readCopy(at: copy)
    }

    struct JoinTable {
        let table: String
        let snippets: String
        let lists: String
    }

    /// Core Data names a many-to-many join table after the order of its entities (`Z_6LISTS`, columns `Z_6SNIPPETS` and
    /// `Z_13LISTS` in the version this was written against), and the numbers change when Paste's model does. The table
    /// is found by what its two columns end in.
    static func joinTable(in db: OpaquePointer) -> JoinTable? {
        var statement: OpaquePointer?
        let tables = "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'Z\\_%' ESCAPE '\\'"
        guard sqlite3_prepare_v2(db, tables, -1, &statement, nil) == SQLITE_OK, let rows = statement else { return nil }
        var names: [String] = []
        while sqlite3_step(rows) == SQLITE_ROW {
            names.append(text(rows, 0) ?? "")
        }
        sqlite3_finalize(rows)
        for name in names.sorted() where name.hasSuffix("LISTS") {
            let columns = columnNames(of: name, in: db)
            let snippets = columns.first { $0.range(of: #"^Z_\d+SNIPPETS$"#, options: .regularExpression) != nil }
            let lists = columns.first { $0.range(of: #"^Z_\d+LISTS$"#, options: .regularExpression) != nil }
            if let snippets, let lists, columns.count == 2 { return JoinTable(
                table: name,
                snippets: snippets,
                lists: lists
            ) }
        }
        return nil
    }

    private static func columnNames(of table: String, in db: OpaquePointer) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(table)\")", -1, &statement, nil) == SQLITE_OK,
              let rows = statement else { return [] }
        defer { sqlite3_finalize(rows) }
        var names: [String] = []
        while sqlite3_step(rows) == SQLITE_ROW {
            names.append(text(rows, 1) ?? "")
        }
        return names
    }

    private static func readCopy(at url: URL) throws -> PasteLibrary {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw ReadError.unreadable
        }
        defer { sqlite3_close(db) }

        guard let join = joinTable(in: db) else { throw ReadError.notAPasteLibrary }
        let query = """
        SELECT l.ZNAME, l.Z_ENT = (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'PasteboardHistory'),
               s.ZTITLE, COALESCE(s.ZCREATEDAT, s.ZTIMESTAMP), a.ZBUNDLEIDENTIFIER, d.ZPASTEBOARDITEMS
        FROM ZSNIPPETLIST l
        JOIN \(join.table) j ON j.\(join.lists) = l.Z_PK
        JOIN ZSNIPPET s ON s.Z_PK = j.\(join.snippets)
        LEFT JOIN ZAPPLICATION a ON a.Z_PK = s.ZSOURCEAPPLICATION
        LEFT JOIN ZSNIPPETDATA d ON d.ZSNIPPET = s.Z_PK
        ORDER BY l.ZDISPLAYORDER, s.ZDISPLAYORDERINPINBOARD, s.Z_PK
        LIMIT \(maxRecords + 1)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let rows = statement else {
            throw ReadError.notAPasteLibrary
        }
        defer { sqlite3_finalize(rows) }

        var order: [String] = []
        var byBoard: [String: [PasteImportRecord]] = [:]
        var history: [PasteImportRecord] = []
        var seen = 0
        var status = sqlite3_step(rows)
        while status == SQLITE_ROW {
            defer { status = sqlite3_step(rows) }
            seen += 1
            guard seen <= maxRecords else { throw ReadError.tooLarge }
            guard let blob = blob(rows, 5), blob.count <= maxRecordBytes,
                  let representations = PasteArchiveDecoder.representations(in: blob) else { continue }
            let board = text(rows, 0) ?? "Imported from Paste"
            let isHistory = sqlite3_column_int(rows, 1) != 0
            let record = PasteImportRecord(
                pinboard: isHistory ? nil : board,
                title: text(rows, 2).flatMap { $0.isEmpty ? nil : $0 },
                timestamp: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(rows, 3)),
                sourceBundleID: text(rows, 4),
                representations: representations
            )
            if isHistory {
                history.append(record)
            } else {
                if byBoard[board] == nil { order.append(board) }
                byBoard[board, default: []].append(record)
            }
        }
        // The loop also ends on an error (a damaged page, a busy file), and a library that is merely short must not be
        // reported as the whole library.
        guard status == SQLITE_DONE else { throw ReadError.unreadable }
        return PasteLibrary(
            pinboards: order.map { .init(name: $0, records: byBoard[$0] ?? []) },
            history: history
        )
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}

/// `ZPASTEBOARDITEMS` is one marker byte followed by an `NSKeyedArchiver` archive of `[PasteCore.PasteboardItem]`;
/// each item holds `types` (UTIs in order) and `data` (UTI → bytes). A stand-in class answers to Paste's class name,
/// so nothing of Paste's is needed and secure decoding allows only plain Foundation containers.
enum PasteArchiveDecoder {
    @objc(PestoDecodedPasteItem)
    private final class Item: NSObject, NSSecureCoding {
        static var supportsSecureCoding: Bool {
            true
        }

        let types: [String]
        let data: [String: Data]

        required init?(coder: NSCoder) {
            types = coder.decodeObject(of: [NSArray.self, NSString.self], forKey: "types") as? [String] ?? []
            data = coder.decodeObject(of: [NSDictionary.self, NSString.self, NSData.self], forKey: "data")
                as? [String: Data] ?? [:]
        }

        func encode(with _: NSCoder) {}
    }

    static func representations(in blob: Data) -> [PasteImportRecord.Representation]? {
        guard blob.count > 1,
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: blob.dropFirst()) else { return nil }
        unarchiver.requiresSecureCoding = true
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        unarchiver.setClass(Item.self, forClassName: "PasteCore.PasteboardItem")
        defer { unarchiver.finishDecoding() }
        guard let items = unarchiver.decodeObject(of: [NSArray.self, Item.self], forKey: NSKeyedArchiveRootObjectKey)
            as? [Item], let first = items.first else { return nil }
        let ordered = first.types.filter { first.data[$0] != nil }
        let representations = ordered.compactMap { uti in
            first.data[uti].map { PasteImportRecord.Representation(uti: uti, dataBase64: $0.base64EncodedString()) }
        }
        return representations.isEmpty ? nil : representations
    }
}
