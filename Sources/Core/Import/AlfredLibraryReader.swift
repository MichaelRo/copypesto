// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// Alfred keeps its clipboard history in `clipboard.alfdb`, one `clipboard` table: the text in `item`, the time in
/// `ts`,
/// the app in `app` and `apppath`, and `dataType` (0 text, 1 picture, 2 file).
public enum AlfredLibraryReader {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Alfred/Databases/clipboard.alfdb")
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: "clipboard.alfdb") { db in
            guard Reader.hasTables(db, ["clipboard"]) else { throw Reader.ReadError.notRecognized }
            let rows = try Reader.prepare(
                db, "SELECT item, ts, apppath, dataType FROM clipboard ORDER BY ts LIMIT \(Reader.maxRecords + 1)"
            )
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
        guard let item = Reader.text(rows, 0), !item.isEmpty else { return nil }
        let representation: PasteImportRecord.Representation
        switch sqlite3_column_int(rows, 3) {
        case 0:
            representation = .init(uti: "public.utf8-plain-text", dataBase64: Data(item.utf8).base64EncodedString())
        case 2 where item.hasPrefix("/"):
            let url = URL(fileURLWithPath: item).absoluteString
            representation = .init(uti: "public.file-url", dataBase64: Data(url.utf8).base64EncodedString())
        default:
            return nil
        }
        let time = sqlite3_column_double(rows, 1)
        // A Unix time is past a billion seconds; one counted from 2001 (Core Data) is not.
        let date = time > 1_000_000_000 && time < 4_000_000_000
            ? Date(timeIntervalSince1970: time) : Date(timeIntervalSinceReferenceDate: time)
        let bundleID = Reader.text(rows, 2).flatMap { Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier }
        return PasteImportRecord(
            pinboard: nil, title: nil, timestamp: date, sourceBundleID: bundleID, representations: [representation]
        )
    }
}
