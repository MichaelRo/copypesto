// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// Maccy 2 keeps its history in a SwiftData store: `ZHISTORYITEM` (app, copy times, pin) and `ZHISTORYITEMCONTENT`
/// (one row for each pasteboard type, its bytes in `ZVALUE`).
public enum MaccyLibraryReader {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: "Storage.sqlite") { db in
            guard Reader.hasTables(db, ["ZHISTORYITEM", "ZHISTORYITEMCONTENT"]) else {
                throw Reader.ReadError.notRecognized
            }
            let rows = try Reader.prepare(db, """
            SELECT i.Z_PK, i.ZAPPLICATION, COALESCE(i.ZLASTCOPIEDAT, i.ZFIRSTCOPIEDAT), i.ZPIN, c.ZTYPE, c.ZVALUE
            FROM ZHISTORYITEM i LEFT JOIN ZHISTORYITEMCONTENT c ON c.ZITEM = i.Z_PK
            ORDER BY i.ZLASTCOPIEDAT, i.Z_PK, c.Z_PK
            """)
            defer { sqlite3_finalize(rows) }

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
                guard let type = Reader.text(rows, 4), let value = Reader.blob(rows, 5), !value.isEmpty,
                      value.count <= Reader.maxValueBytes else { continue }
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
                    timestamp: item.time > 0 ? Date(timeIntervalSinceReferenceDate: item.time) : .now,
                    sourceBundleID: item.application,
                    representations: item.representations
                ))
            }
            return ClipboardAppLibrary(records: records, skipped: skipped)
        }
    }
}
