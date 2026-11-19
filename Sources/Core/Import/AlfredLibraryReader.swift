// SPDX-License-Identifier: MIT
#if os(macOS)
import Foundation
import SQLite3

/// Alfred keeps its clipboard history in `clipboard.alfdb`, one `clipboard` table: the text in `item`, the time in
/// `ts`, the app in `app` and `apppath`, `dataType` (0 text, 1 picture, 2 file), and `dataHash` for external payloads
/// stored under `<url.path>.data/<dataHash>`.
public enum AlfredLibraryReader {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Alfred/Databases/clipboard.alfdb")
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        let dataFolder = URL(fileURLWithPath: url.path + ".data", isDirectory: true)
        return try Reader.withCopy(of: url, named: "clipboard.alfdb") { db in
            guard Reader.hasTables(db, ["clipboard"]) else { throw Reader.ReadError.notRecognized }
            let columns = Reader.columnNames(of: "clipboard", in: db)
            guard columns.contains("item"), columns.contains("ts") else { throw Reader.ReadError.notRecognized }
            let appPathExpr = columns.contains("apppath") ? "apppath" : "NULL"
            let dataTypeExpr = columns.contains("dataType") ? "dataType" : "0"
            let dataHashExpr = columns.contains("dataHash") ? "dataHash" : "NULL"
            let query = """
            SELECT item, ts, \(appPathExpr), \(dataTypeExpr), \(dataHashExpr)
            FROM clipboard ORDER BY ts LIMIT \(Reader.maxRecords + 1)
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
                guard let record = record(from: rows, dataFolder: dataFolder) else {
                    skipped += 1
                    continue
                }
                records.append(record)
            }
            guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
            return ClipboardAppLibrary(records: records, skipped: skipped)
        }
    }

    private static func record(from rows: OpaquePointer, dataFolder: URL) -> PasteImportRecord? {
        typealias Reader = ClipboardAppLibraryReader
        let item = Reader.text(rows, 0)
        let dataType = sqlite3_column_int(rows, 3)
        let dataHash = Reader.text(rows, 4)
        guard let representation = representation(
            dataType: dataType, item: item, dataHash: dataHash, dataFolder: dataFolder
        ) else {
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

    private static func representation(
        dataType: Int32,
        item: String?,
        dataHash: String?,
        dataFolder: URL
    )
    -> PasteImportRecord.Representation? {
        typealias Reader = ClipboardAppLibraryReader
        switch dataType {
        case 0:
            guard let item, !item.isEmpty else { return nil }
            return .init(uti: "public.utf8-plain-text", dataBase64: Data(item.utf8).base64EncodedString())
        case 1:
            guard let dataHash, Reader.isPlainFileName(dataHash),
                  let data = Reader.readExternalFile(named: dataHash, in: dataFolder) else { return nil }
            let ext = (dataHash as NSString).pathExtension
            guard let uti = ext.isEmpty
                ? Reader.imageUTI(forBytes: data)
                : Reader.imageUTI(forExtension: ext) else { return nil }
            return .init(uti: uti, dataBase64: data.base64EncodedString())
        case 2:
            if let urls = fileURLsFromPlist(dataHash: dataHash, in: dataFolder) {
                let encoded = FileClip.encode(urls)
                return .init(uti: "public.file-url", dataBase64: Data(encoded.utf8).base64EncodedString())
            }
            guard let item, item.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: item).absoluteString
            return .init(uti: "public.file-url", dataBase64: Data(url.utf8).base64EncodedString())
        default:
            return nil
        }
    }

    private static func fileURLsFromPlist(dataHash: String?, in dataFolder: URL) -> [URL]? {
        typealias Reader = ClipboardAppLibraryReader
        guard let dataHash, dataHash.lowercased().hasSuffix(".plist"),
              Reader.isPlainFileName(dataHash),
              let data = Reader.readExternalFile(named: dataHash, in: dataFolder),
              let paths = (try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              )) as? [String] else { return nil }
        let urls: [URL] = paths.compactMap { path in
            if path.hasPrefix("file://") { return URL(string: path) }
            if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
            return nil
        }
        return urls.isEmpty ? nil : urls
    }
}
#endif
