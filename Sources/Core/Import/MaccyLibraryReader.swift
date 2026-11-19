// SPDX-License-Identifier: MIT
#if os(macOS)
import Foundation
import SQLite3

/// Maccy keeps its history in SwiftData (`Storage.sqlite`, 2.x) or Core Data (`CoreData.sqlite`, 1.x):
/// `ZHISTORYITEM` (app, copy times, pin) and `ZHISTORYITEMCONTENT` (pasteboard types and `ZVALUE` blobs).
public enum MaccyLibraryReader {
    public static func candidateDatabaseURLs(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    )
    -> [URL] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent(
                "Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"
            ),
            library.appendingPathComponent("Application Support/Maccy/Storage.sqlite"),
            library.appendingPathComponent(
                "Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/CoreData.sqlite"
            ),
            library.appendingPathComponent("Application Support/Maccy/CoreData.sqlite")
        ]
    }

    public static var defaultDatabaseURL: URL {
        let candidates = candidateDatabaseURLs()
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: url.lastPathComponent) { db, externalFolder in
            guard Reader.hasTables(db, ["ZHISTORYITEM", "ZHISTORYITEMCONTENT"]) else {
                throw Reader.ReadError.notRecognized
            }
            let query = try makeQuery(in: db)
            let rows = try Reader.prepare(db, query)
            defer { sqlite3_finalize(rows) }
            return try collectRecords(from: rows, externalFolder: externalFolder)
        }
    }

    private static func makeQuery(in db: OpaquePointer) throws -> String {
        typealias Reader = ClipboardAppLibraryReader
        let itemCols = Reader.columnNames(of: "ZHISTORYITEM", in: db)
        let contentCols = Reader.columnNames(of: "ZHISTORYITEMCONTENT", in: db)
        guard itemCols.contains("Z_PK"), contentCols.contains("ZITEM"),
              contentCols.contains("ZTYPE"), contentCols.contains("ZVALUE") else
        {
            throw Reader.ReadError.notRecognized
        }
        let appExpr = itemCols.contains("ZAPPLICATION") ? "i.ZAPPLICATION" : "NULL"
        let timeExpr = switch (itemCols.contains("ZLASTCOPIEDAT"), itemCols.contains("ZFIRSTCOPIEDAT")) {
        case (true, true): "COALESCE(i.ZLASTCOPIEDAT, i.ZFIRSTCOPIEDAT)"
        case (true, false): "i.ZLASTCOPIEDAT"
        case (false, true): "i.ZFIRSTCOPIEDAT"
        case (false, false): "0"
        }
        let orderTime = itemCols.contains("ZLASTCOPIEDAT")
            ? "i.ZLASTCOPIEDAT, "
            : (itemCols.contains("ZFIRSTCOPIEDAT") ? "i.ZFIRSTCOPIEDAT, " : "")
        let pinExpr = itemCols.contains("ZPIN") ? "i.ZPIN" : "NULL"
        return """
        SELECT i.Z_PK, \(appExpr), \(timeExpr), \(pinExpr), c.ZTYPE, c.ZVALUE
        FROM ZHISTORYITEM i LEFT JOIN ZHISTORYITEMCONTENT c ON c.ZITEM = i.Z_PK
        ORDER BY \(orderTime)i.Z_PK, c.Z_PK
        """
    }

    private static func collectRecords(
        from rows: OpaquePointer,
        externalFolder: URL
    ) throws
    -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        struct Pending {
            var application: String?
            var time: Double
            var pinned: Bool
            var representations: [PasteImportRecord.Representation] = []
        }
        var order: [Int64] = []
        var items: [Int64: Pending] = [:]
        var status = sqlite3_step(rows)
        while status == SQLITE_ROW {
            defer { status = sqlite3_step(rows) }
            let key = sqlite3_column_int64(rows, 0)
            if items[key] == nil {
                guard order.count < Reader.maxRecords else { throw Reader.ReadError.tooLarge }
                order.append(key)
                items[key] = Pending(
                    application: Reader.text(rows, 1),
                    time: sqlite3_column_double(rows, 2),
                    pinned: !(Reader.text(rows, 3) ?? "").isEmpty
                )
            }
            guard let type = Reader.text(rows, 4),
                  let value = Reader.blob(rows, 5, externalFolder: externalFolder),
                  !value.isEmpty, value.count <= Reader.maxValueBytes else { continue }
            items[key]?.representations.append(.init(uti: type, dataBase64: value.base64EncodedString()))
        }
        guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }

        var records: [PasteImportRecord] = []
        var skipped = 0
        for key in order {
            guard let item = items[key], !item.representations.isEmpty else {
                skipped += 1
                continue
            }
            records.append(PasteImportRecord(
                pinboard: item.pinned ? "Pinned in Maccy" : nil,
                title: nil,
                timestamp: Reader.date(from: item.time),
                sourceBundleID: item.application,
                representations: item.representations
            ))
        }
        return ClipboardAppLibrary(records: records, skipped: skipped)
    }
}
#endif
