// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// Pastebot keeps its clipboard history in a CoreData SQLite database (`Pastebot.sqlite`).
public enum PastebotLibraryReader {
    public static var defaultDatabaseURL: URL {
        let primary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.tapbots.Pastebot3Mac/Data/Library/Application Support/Pastebot/Pastebot.sqlite"
        )
        if FileManager.default.fileExists(atPath: primary.path) { return primary }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.tapbots.PastebotMac/Data/Library/Application Support/Pastebot/Pastebot.sqlite"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: "Pastebot.sqlite") { db in
            guard Reader.hasTables(db, ["ZCLIP", "ZPASTEBOARDDATA"]) || Reader.hasTables(db, ["ZCLIP"]) else {
                throw Reader.ReadError.notRecognized
            }
            let hasDataJoin = Reader.hasTables(db, ["ZPASTEBOARDDATA"])
            let query = hasDataJoin
                ? """
                SELECT c.Z_PK, c.ZTITLE, c.ZTIMESTAMP, c.ZBUNDLEIDENTIFIER, d.ZTYPE, d.ZDATA
                FROM ZCLIP c LEFT JOIN ZPASTEBOARDDATA d ON d.ZCLIP = c.Z_PK
                ORDER BY c.ZTIMESTAMP, c.Z_PK
                """
                : "SELECT Z_PK, ZTITLE, ZTIMESTAMP, ZBUNDLEIDENTIFIER, NULL, NULL FROM ZCLIP ORDER BY ZTIMESTAMP"
            let rows = try Reader.prepare(db, query)
            defer { sqlite3_finalize(rows) }

            var order: [Int64] = []
            var items: [Int64: PendingItem] = [:]
            var status = sqlite3_step(rows)
            while status == SQLITE_ROW {
                defer { status = sqlite3_step(rows) }
                let key = sqlite3_column_int64(rows, 0)
                if items[key] == nil {
                    guard order.count < Reader.maxRecords else { throw Reader.ReadError.tooLarge }
                    order.append(key)
                    items[key] = PendingItem(
                        title: Reader.text(rows, 1),
                        time: sqlite3_column_double(rows, 2),
                        bundleID: Reader.text(rows, 3)
                    )
                }
                if let type = Reader.text(rows, 4), let data = Reader.blob(rows, 5), !data.isEmpty,
                   data.count <= Reader.maxValueBytes
                {
                    items[key]?.reps.append(.init(uti: type, dataBase64: data.base64EncodedString()))
                }
            }
            guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }

            return buildLibrary(order: order, items: items)
        }
    }

    private static func buildLibrary(order: [Int64], items: [Int64: PendingItem]) -> ClipboardAppLibrary {
        var records: [PasteImportRecord] = []
        var skipped = 0
        for key in order {
            guard let item = items[key], !item.reps.isEmpty else {
                skipped += 1
                continue
            }
            let date = item.time > 1_000_000_000
                ? Date(timeIntervalSince1970: item.time)
                : (item.time > 0 ? Date(timeIntervalSinceReferenceDate: item.time) : .now)
            records.append(PasteImportRecord(
                pinboard: nil,
                title: item.title,
                timestamp: date,
                sourceBundleID: item.bundleID,
                representations: item.reps
            ))
        }
        return ClipboardAppLibrary(records: records, skipped: skipped)
    }

    private struct PendingItem {
        var title: String?
        var time: Double
        var bundleID: String?
        var reps: [PasteImportRecord.Representation] = []
    }
}
