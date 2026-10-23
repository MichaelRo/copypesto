// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// CleanClip stores its clips in SQLite (`Storage.sqlite`).
public enum CleanClipLibraryReader {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/CleanClip/Storage.sqlite"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: "Storage.sqlite") { db in
            guard Reader.hasTables(db, ["ZHISTORYITEM", "ZHISTORYITEMCONTENT"]) else {
                throw Reader.ReadError.notRecognized
            }
            let rows = try Reader.prepare(db, """
            SELECT i.Z_PK, i.ZAPPLICATION, COALESCE(i.ZLASTCOPIEDAT, i.ZFIRSTCOPIEDAT), \
            i.ZPIN, i.ZTITLE, c.ZTYPE, c.ZMETADATA, c.ZVALUE
            FROM ZHISTORYITEM i LEFT JOIN ZHISTORYITEMCONTENT c ON c.ZITEM = i.Z_PK
            ORDER BY i.ZLASTCOPIEDAT, i.Z_PK, c.Z_PK
            """)
            defer { sqlite3_finalize(rows) }

            var order: [Int64] = []
            var items: [Int64: Pending] = [:]
            var status = sqlite3_step(rows)
            while status == SQLITE_ROW {
                defer { status = sqlite3_step(rows) }
                let key = sqlite3_column_int64(rows, 0)
                if items[key] == nil {
                    guard order.count < Reader.maxRecords else { throw Reader.ReadError.tooLarge }
                    order.append(key)
                    let pinStr = Reader.text(rows, 3)
                    let isPinned = pinStr != nil && pinStr != "0" && !(pinStr?.isEmpty ?? true)
                    items[key] = Pending(
                        app: Reader.text(rows, 1),
                        time: sqlite3_column_double(rows, 2),
                        pinned: isPinned,
                        title: Reader.text(rows, 4)
                    )
                }
                let type = Reader.text(rows, 5) ?? "public.utf8-plain-text"
                if let blob = Reader.blob(rows, 7), !blob.isEmpty, blob.count <= Reader.maxValueBytes {
                    items[key]?.representations.append(.init(uti: type, dataBase64: blob.base64EncodedString()))
                } else if let meta = Reader.text(rows, 6), !meta.isEmpty {
                    items[key]?.representations.append(
                        .init(uti: type, dataBase64: Data(meta.utf8).base64EncodedString())
                    )
                }
            }
            guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
            return buildLibrary(order: order, items: items)
        }
    }

    private static func buildLibrary(order: [Int64], items: [Int64: Pending]) -> ClipboardAppLibrary {
        var records: [PasteImportRecord] = []
        var skipped = 0
        for key in order {
            guard let item = items[key] else { continue }
            var reps = item.representations
            if reps.isEmpty, let title = item.title, !title.isEmpty {
                reps.append(.init(uti: "public.utf8-plain-text", dataBase64: Data(title.utf8).base64EncodedString()))
            }
            guard !reps.isEmpty else {
                skipped += 1
                continue
            }
            let date = item.time > 1_000_000_000
                ? Date(timeIntervalSince1970: item.time)
                : (item.time > 0 ? Date(timeIntervalSinceReferenceDate: item.time) : .now)
            records.append(PasteImportRecord(
                pinboard: item.pinned ? "Pinned in CleanClip" : nil,
                title: item.title,
                timestamp: date,
                sourceBundleID: item.app,
                representations: reps
            ))
        }
        return ClipboardAppLibrary(records: records, skipped: skipped)
    }

    private struct Pending {
        var app: String?
        var time: Double
        var pinned: Bool
        var title: String?
        var representations: [PasteImportRecord.Representation] = []
    }
}
