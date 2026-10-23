// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// CopyClip stores its plain-text clipboard history in an SQLite database.
public enum CopyClipLibraryReader {
    public static var defaultDatabaseURL: URL {
        let primary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.fiplab.clipboard/Data/Library/Application Support/CopyClip/copyclip.sqlite"
        )
        if FileManager.default.fileExists(atPath: primary.path) { return primary }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.fiplab.copyclip/Data/Library/Application Support/CopyClip/CopyClip.sqlite"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: "CopyClip.sqlite") { db in
            let isModern = Reader.hasTables(db, ["ZCLIPPING"])
            let isLegacyCoreData = !isModern && Reader.hasTables(db, ["ZCLIPITEM"])
            let isSqlite = !isModern && !isLegacyCoreData && Reader.hasTables(db, ["clips"])
            guard isModern || isLegacyCoreData || isSqlite else { throw Reader.ReadError.notRecognized }
            let query = isModern
                ? """
                SELECT c.ZCONTENTS, c.ZDATERECORDED FROM ZCLIPPING c \
                ORDER BY c.ZDATERECORDED LIMIT \(Reader.maxRecords + 1)
                """
                : (isLegacyCoreData
                    ? "SELECT ZCONTENT, ZDATE FROM ZCLIPITEM ORDER BY ZDATE LIMIT \(Reader.maxRecords + 1)"
                    : "SELECT content, created_at FROM clips ORDER BY created_at LIMIT \(Reader.maxRecords + 1)")
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
                guard let text = Reader.text(rows, 0), !text.isEmpty else {
                    skipped += 1
                    continue
                }
                let rawTime = sqlite3_column_double(rows, 1)
                let date = rawTime > 1_000_000_000
                    ? Date(timeIntervalSince1970: rawTime)
                    : (rawTime > 0 ? Date(timeIntervalSinceReferenceDate: rawTime) : .now)
                records.append(PasteImportRecord(
                    pinboard: nil,
                    title: nil,
                    timestamp: date,
                    sourceBundleID: "com.fiplab.clipboard",
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
