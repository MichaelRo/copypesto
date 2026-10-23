// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// PasteNow stores clips in an SQLite database (`PasteNow.sqlite`).
public enum PasteNowLibraryReader {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Group Containers/KAQ3M6FSM7.app.pastenow.PasteNow/Documents/PasteNow.sqlite"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: "PasteNow.sqlite") { db in
            guard Reader.hasTables(db, ["ZPASTEITEM"]) else {
                throw Reader.ReadError.notRecognized
            }
            let hasLists = Reader.hasTables(db, ["ZPASTELIST"])
            let query = hasLists
                ? """
                SELECT i.Z_PK, i.ZTITLE, i.ZTEXT, i.ZTIMESTAMP, i.ZAPPBUNDLEID, i.ZRTFDATA, i.ZURLDATA, l.ZNAME
                FROM ZPASTEITEM i LEFT JOIN ZPASTELIST l ON l.Z_PK = i.ZLIST
                ORDER BY i.ZTIMESTAMP, i.Z_PK LIMIT \(Reader.maxRecords + 1)
                """
                : """
                SELECT i.Z_PK, i.ZTITLE, i.ZTEXT, i.ZTIMESTAMP, i.ZAPPBUNDLEID, i.ZRTFDATA, i.ZURLDATA, NULL
                FROM ZPASTEITEM i ORDER BY i.ZTIMESTAMP, i.Z_PK LIMIT \(Reader.maxRecords + 1)
                """
            let rows = try Reader.prepare(db, query)
            defer { sqlite3_finalize(rows) }

            var records: [PasteImportRecord] = []
            var skipped = 0
            var seen = 0
            var status = sqlite3_step(rows)
            while status == SQLITE_ROW {
                defer { status = sqlite3_step(rows) }
                seen += 1
                guard seen <= Reader.maxRecords else { throw Reader.ReadError.tooLarge }
                guard let record = record(from: rows) else {
                    skipped += 1
                    continue
                }
                records.append(record)
            }
            guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
            return ClipboardAppLibrary(records: records, skipped: skipped)
        }
    }

    private static func record(from rows: OpaquePointer) -> PasteImportRecord? {
        typealias Reader = ClipboardAppLibraryReader
        var reps: [PasteImportRecord.Representation] = []
        if let text = Reader.text(rows, 2), !text.isEmpty {
            reps.append(.init(uti: "public.utf8-plain-text", dataBase64: Data(text.utf8).base64EncodedString()))
        }
        if let rtf = Reader.blob(rows, 5), !rtf.isEmpty, rtf.count <= Reader.maxValueBytes {
            reps.append(.init(uti: "public.rtf", dataBase64: rtf.base64EncodedString()))
        }
        if let urlData = Reader.blob(rows, 6), !urlData.isEmpty, urlData.count <= Reader.maxValueBytes {
            reps.append(.init(uti: "public.url", dataBase64: urlData.base64EncodedString()))
        }
        guard !reps.isEmpty else { return nil }
        let time = sqlite3_column_double(rows, 3)
        let date = time > 1_000_000_000
            ? Date(timeIntervalSince1970: time)
            : (time > 0 ? Date(timeIntervalSinceReferenceDate: time) : .now)
        let listName = Reader.text(rows, 7)
        let pinboard = (listName != nil && listName != "All" && !(listName?.isEmpty ?? true)) ? listName : nil
        return PasteImportRecord(
            pinboard: pinboard,
            title: Reader.text(rows, 1),
            timestamp: date,
            sourceBundleID: Reader.text(rows, 4),
            representations: reps
        )
    }
}
