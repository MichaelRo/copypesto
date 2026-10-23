// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// Clipy stores history in an SQLite database (`sqlite.db`).
public enum ClipyLibraryReader {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/com.clipy-app.Clipy/sqlite.db"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: "sqlite.db") { db in
            guard Reader.hasTables(db, ["pasteboardHistories", "pasteboardHistoryAssets"]) else {
                throw Reader.ReadError.notRecognized
            }
            let rows = try Reader.prepare(db, """
            SELECT h.id, h.title, h.updateAt, a.pasteboardType, a.data
            FROM pasteboardHistories h LEFT JOIN pasteboardHistoryAssets a ON a.pasteboardHistoryID = h.id
            ORDER BY h.updateAt, h.id, a."index"
            """)
            defer { sqlite3_finalize(rows) }

            struct Pending {
                var title: String?
                var time: Double
                var reps: [PasteImportRecord.Representation] = []
            }
            var order: [String] = []
            var items: [String: Pending] = [:]
            var status = sqlite3_step(rows)
            while status == SQLITE_ROW {
                defer { status = sqlite3_step(rows) }
                guard let id = Reader.text(rows, 0) else { continue }
                if items[id] == nil {
                    guard order.count < Reader.maxRecords else { throw Reader.ReadError.tooLarge }
                    order.append(id)
                    items[id] = Pending(
                        title: Reader.text(rows, 1),
                        time: Double(sqlite3_column_int64(rows, 2))
                    )
                }
                guard let type = Reader.text(rows, 3), let data = Reader.blob(rows, 4), !data.isEmpty,
                      data.count <= Reader.maxValueBytes else { continue }
                items[id]?.reps.append(.init(uti: type, dataBase64: data.base64EncodedString()))
            }
            guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }

            var records: [PasteImportRecord] = []
            var skipped = 0
            for id in order {
                guard let item = items[id], !item.reps.isEmpty else {
                    skipped += 1
                    continue
                }
                let date = item.time > 1_000_000_000
                    ? Date(timeIntervalSince1970: item.time)
                    : (item.time > 0 ? Date(timeIntervalSinceReferenceDate: item.time) : .now)
                records.append(PasteImportRecord(
                    pinboard: nil,
                    title: (item.title?.isEmpty ?? true) ? nil : item.title,
                    timestamp: date,
                    sourceBundleID: "com.clipy-app.Clipy",
                    representations: item.reps
                ))
            }
            return ClipboardAppLibrary(records: records, skipped: skipped)
        }
    }
}
