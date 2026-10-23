// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// PastePal stores clips in a CoreData store (`PastePal2.sqlite`, `PastePal.sqlite` or `Model.sqlite`).
public enum PastePalLibraryReader {
    public static var defaultDatabaseURL: URL {
        let primary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.onmyway133.PastePal/Data/Library/Application Support/PastePal/PastePal2.sqlite"
        )
        if FileManager.default.fileExists(atPath: primary.path) { return primary }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.cmhaertling.PastePal/Data/Library/Application Support/PastePal/PastePal.sqlite"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: "PastePal.sqlite") { db in
            let isModern = Reader.hasTables(db, ["ZCDCLIPBOARDITEM"])
            let isLegacy = !isModern && Reader.hasTables(db, ["ZPASTEDITEM"])
            guard isModern || isLegacy else {
                throw Reader.ReadError.notRecognized
            }
            let query = isModern
                ? """
                SELECT Z_PK, ZSTRING, ZCREATEDAT, ZAPPBUNDLEID, ZISPINNED
                FROM ZCDCLIPBOARDITEM ORDER BY ZCREATEDAT LIMIT \(Reader.maxRecords + 1)
                """
                : """
                SELECT Z_PK, ZTEXT, ZDATE, ZSOURCEAPPBUNDLEIDENTIFIER, ZISPINNED
                FROM ZPASTEDITEM ORDER BY ZDATE LIMIT \(Reader.maxRecords + 1)
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
                guard let text = Reader.text(rows, 1), !text.isEmpty else {
                    skipped += 1
                    continue
                }
                let rawTime = sqlite3_column_double(rows, 2)
                let date = rawTime > 1_000_000_000
                    ? Date(timeIntervalSince1970: rawTime)
                    : (rawTime > 0 ? Date(timeIntervalSinceReferenceDate: rawTime) : .now)
                let isPinned = sqlite3_column_int(rows, 4) != 0
                records.append(PasteImportRecord(
                    pinboard: isPinned ? "Pinned in PastePal" : nil,
                    title: nil,
                    timestamp: date,
                    sourceBundleID: Reader.text(rows, 3),
                    representations: [.init(
                        uti: "public.utf8-plain-text",
                        dataBase64: Data(text.utf8).base64EncodedString()
                    )]
                ))
            }
            guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
            return ClipboardAppLibrary(records: records, skipped: skipped)
        }
    }
}
