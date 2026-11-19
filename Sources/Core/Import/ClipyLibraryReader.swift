// SPDX-License-Identifier: MIT
#if os(macOS)
import AppKit
import Foundation
import SQLite3

/// Clipy stores history and snippets in an SQLite database (`sqlite.db`).
public enum ClipyLibraryReader {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/com.clipy-app.Clipy/sqlite.db"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: "sqlite.db") { db in
            let tables = Reader.tableNames(in: db)
            guard tables.contains("pasteboardHistories"), tables.contains("pasteboardHistoryAssets") else {
                throw Reader.ReadError.notRecognized
            }
            var (records, skipped) = try readHistory(in: db, hasThumbnails: tables.contains(
                "pasteboardHistoryThumbnailAssets"
            ))
            if tables.contains("snippets"), tables.contains("snippetFolders") {
                let snippetResult = try readSnippets(in: db, remainingCapacity: Reader.maxRecords - records.count)
                records.append(contentsOf: snippetResult.records)
                skipped += snippetResult.skipped
            }
            return ClipboardAppLibrary(records: records, skipped: skipped)
        }
    }

    private static func readHistory(
        in db: OpaquePointer,
        hasThumbnails: Bool
    ) throws
    -> (records: [PasteImportRecord], skipped: Int) {
        typealias Reader = ClipboardAppLibraryReader
        let thumbnails = hasThumbnails ? readThumbnails(in: db) : [:]
        let assetCols = Reader.columnNames(of: "pasteboardHistoryAssets", in: db)
        let orderClause = assetCols.contains("index")
            ? "ORDER BY h.updateAt, h.id, a.\"index\""
            : "ORDER BY h.updateAt, h.id"
        let rows = try Reader.prepare(db, """
        SELECT h.id, h.title, h.updateAt, a.pasteboardType, a.data
        FROM pasteboardHistories h LEFT JOIN pasteboardHistoryAssets a ON a.pasteboardHistoryID = h.id
        \(orderClause)
        """)
        defer { sqlite3_finalize(rows) }

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
            guard let type = Reader.text(rows, 3),
                  let data = Reader.blob(rows, 4, unwrapsInlineMarker: false),
                  !data.isEmpty else { continue }
            items[id]?.reps.append(.init(uti: type, dataBase64: data.base64EncodedString()))
        }
        guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
        return buildHistoryRecords(order: order, items: items, thumbnails: thumbnails)
    }

    private struct Pending {
        var title: String?
        var time: Double
        var reps: [PasteImportRecord.Representation] = []
    }

    private static func buildHistoryRecords(
        order: [String],
        items: [String: Pending],
        thumbnails: [String: Data]
    )
    -> (records: [PasteImportRecord], skipped: Int) {
        var records: [PasteImportRecord] = []
        var skipped = 0
        for id in order {
            guard let item = items[id] else { continue }
            var reps = item.reps
            let hasImage = reps.contains {
                PasteboardTypeDetector.clipboardType(for: NSPasteboard.PasteboardType($0.uti)) == .image
            }
            if !hasImage, let thumb = thumbnails[id] {
                reps.append(.init(uti: "public.tiff", dataBase64: thumb.base64EncodedString()))
            }
            if reps.isEmpty, let title = item.title, !title.isEmpty {
                reps.append(.init(uti: "public.utf8-plain-text", dataBase64: Data(title.utf8).base64EncodedString()))
            }
            guard !reps.isEmpty else {
                skipped += 1
                continue
            }
            records.append(PasteImportRecord(
                pinboard: nil,
                title: nil,
                timestamp: ClipboardAppLibraryReader.date(from: item.time),
                sourceBundleID: "com.clipy-app.Clipy",
                representations: reps
            ))
        }
        return (records, skipped)
    }

    private static func readThumbnails(in db: OpaquePointer) -> [String: Data] {
        typealias Reader = ClipboardAppLibraryReader
        let cols = Reader.columnNames(of: "pasteboardHistoryThumbnailAssets", in: db)
        guard cols.contains("pasteboardHistoryID"), cols.contains("kind"), cols.contains("data"),
              let rows = try? Reader.prepare(
                  db, "SELECT pasteboardHistoryID, data FROM pasteboardHistoryThumbnailAssets WHERE kind = 'image'"
              ) else { return [:] }
        defer { sqlite3_finalize(rows) }
        var map: [String: Data] = [:]
        while sqlite3_step(rows) == SQLITE_ROW {
            if let id = Reader.text(rows, 0),
               let data = Reader.blob(rows, 1, unwrapsInlineMarker: false),
               !data.isEmpty
            {
                map[id] = data
            }
        }
        return map
    }

    private static func readSnippets(
        in db: OpaquePointer,
        remainingCapacity: Int
    ) throws
    -> (records: [PasteImportRecord], skipped: Int) {
        typealias Reader = ClipboardAppLibraryReader
        let sCols = Reader.columnNames(of: "snippets", in: db)
        let fCols = Reader.columnNames(of: "snippetFolders", in: db)
        guard sCols.contains("content"), sCols.contains("folderID"), fCols.contains("id") else {
            return ([], 0)
        }
        let sEnabled = sCols.contains("isEnabled") ? "COALESCE(s.isEnabled, 1) != 0" : "1 = 1"
        let fEnabled = fCols.contains("isEnabled") ? "COALESCE(f.isEnabled, 1) != 0" : "1 = 1"
        let sTitleExpr = sCols.contains("title") ? "s.title" : "NULL"
        let fTitleExpr = fCols.contains("title") ? "f.title" : "NULL"
        let orderClause = (fCols.contains("index") && sCols.contains("index"))
            ? "ORDER BY f.\"index\", f.id, s.\"index\", s.id"
            : ""
        let rows = try Reader.prepare(db, """
        SELECT \(sTitleExpr), s.content, \(fTitleExpr)
        FROM snippets s LEFT JOIN snippetFolders f ON f.id = s.folderID
        WHERE \(sEnabled) AND \(fEnabled)
        \(orderClause)
        """)
        defer { sqlite3_finalize(rows) }

        var records: [PasteImportRecord] = []
        var skipped = 0
        var status = sqlite3_step(rows)
        while status == SQLITE_ROW {
            defer { status = sqlite3_step(rows) }
            guard let content = Reader.text(rows, 1), !content.isEmpty,
                  content.utf8.count <= Reader.maxValueBytes else
            {
                skipped += 1
                continue
            }
            guard records.count < remainingCapacity else { throw Reader.ReadError.tooLarge }
            let title = Reader.text(rows, 0).flatMap { $0.isEmpty ? nil : $0 }
            let folder = Reader.text(rows, 2).flatMap { $0.isEmpty ? nil : $0 } ?? "Snippets in Clipy"
            records.append(PasteImportRecord(
                pinboard: folder,
                title: title,
                timestamp: .now,
                sourceBundleID: "com.clipy-app.Clipy",
                representations: [.init(
                    uti: "public.utf8-plain-text", dataBase64: Data(content.utf8).base64EncodedString()
                )]
            ))
        }
        guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
        return (records, skipped)
    }
}
#endif
