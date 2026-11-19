// SPDX-License-Identifier: MIT
#if os(macOS)
import Foundation
import SQLite3

/// Pastebot keeps its clipboard history in a CoreData SQLite database (`Pastebot.sqlite`).
public enum PastebotLibraryReader {
    public static func candidateDatabaseURLs(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    )
    -> [URL] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            library.appendingPathComponent(
                "Containers/com.tapbots.Pastebot3Mac/Data/Library/Application Support/Pastebot/Pastebot.sqlite"
            ),
            library.appendingPathComponent(
                "Group Containers/2775222H9T.com.tapbots.Pastebot3Mac/"
                    + "Library/Application Support/Pastebot/Pastebot.sqlite"
            ),
            library.appendingPathComponent(
                "Group Containers/2775222H9T.com.tapbots.Pastebot3Mac/Pastebot.sqlite"
            ),
            library.appendingPathComponent(
                "Containers/com.tapbots.Pastebot2Mac/Data/Library/Application Support/Pastebot/Pastebot.sqlite"
            ),
            library.appendingPathComponent(
                "Group Containers/2775222H9T.com.tapbots.Pastebot2Mac/"
                    + "Library/Application Support/Pastebot/Pastebot.sqlite"
            ),
            library.appendingPathComponent(
                "Group Containers/2775222H9T.com.tapbots.Pastebot2Mac/Pastebot.sqlite"
            ),
            library.appendingPathComponent(
                "Containers/com.tapbots.PastebotMac/Data/Library/Application Support/Pastebot/Pastebot.sqlite"
            ),
            library.appendingPathComponent("Application Support/Pastebot/Pastebot.sqlite")
        ]
    }

    public static var defaultDatabaseURL: URL {
        let candidates = candidateDatabaseURLs()
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: url.lastPathComponent) { db, externalFolder in
            let tables = Reader.tableNames(in: db)
            guard tables.contains("ZCLIP") else { throw Reader.ReadError.notRecognized }
            let query = try makeQuery(tables: tables, db: db)
            let rows = try Reader.prepare(db, query)
            defer { sqlite3_finalize(rows) }
            return try collectRecords(from: rows, externalFolder: externalFolder)
        }
    }

    private static func makeQuery(tables: Set<String>, db: OpaquePointer) throws -> String {
        typealias Reader = ClipboardAppLibraryReader
        let clipCols = Reader.columnNames(of: "ZCLIP", in: db)
        guard clipCols.contains("Z_PK") else { throw Reader.ReadError.notRecognized }
        let titleExpr = clipCols.contains("ZTITLE") ? "c.ZTITLE" : "NULL"
        let timeCol = ["ZTIMESTAMP", "ZDATE", "ZCREATEDAT"].first { clipCols.contains($0) }
        let timeExpr = timeCol.map { "c.\($0)" } ?? "0"
        let orderTime = timeCol.map { "c.\($0), " } ?? ""
        let bundleCol = ["ZBUNDLEIDENTIFIER", "ZAPPBUNDLEID", "ZSOURCEAPPBUNDLEID"].first { clipCols.contains($0) }
        let bundleExpr = bundleCol.map { "c.\($0)" } ?? "NULL"
        let clipDataExpr = clipCols.contains("ZDATA") ? "c.ZDATA" : "NULL"
        let clipTypeCol = ["ZTYPE", "ZUTI"].first { clipCols.contains($0) }
        let clipTypeExpr = clipTypeCol.map { "c.\($0)" } ?? "NULL"
        let plainCol = ["ZPLAINTEXT", "ZTEXT", "ZSTRING"].first { clipCols.contains($0) }
        let plainExpr = plainCol.map { "c.\($0)" } ?? "NULL"
        let searchExpr = clipCols.contains("ZSEARCHSTRING") ? "c.ZSEARCHSTRING" : "NULL"

        let dataJoin = makeDataJoin(tables: tables, db: db)
        let boardJoin = makeCollectionJoin(tables: tables, clipCols: clipCols, db: db)

        return """
        SELECT c.Z_PK, \(titleExpr), \(timeExpr), \(bundleExpr),
               \(dataJoin.typeExpr), \(dataJoin.dataExpr),
               \(clipDataExpr), \(clipTypeExpr), \(plainExpr), \(searchExpr),
               \(boardJoin.expr)
        FROM ZCLIP c
        \(dataJoin.clause)
        \(boardJoin.clause)
        ORDER BY \(orderTime)c.Z_PK\(dataJoin.orderSuffix)
        """
    }

    private struct DataJoin {
        let typeExpr: String
        let dataExpr: String
        let clause: String
        let orderSuffix: String
    }

    private struct CollectionTarget {
        let table: String
        let alias: String
        let foreignKey: String
    }

    private static func makeDataJoin(
        tables: Set<String>,
        db: OpaquePointer
    )
    -> DataJoin {
        guard tables.contains("ZPASTEBOARDDATA") else {
            return DataJoin(typeExpr: "NULL", dataExpr: "NULL", clause: "", orderSuffix: "")
        }
        let dataCols = ClipboardAppLibraryReader.columnNames(of: "ZPASTEBOARDDATA", in: db)
        guard dataCols.contains("ZCLIP"), dataCols.contains("ZDATA") else {
            return DataJoin(typeExpr: "NULL", dataExpr: "NULL", clause: "", orderSuffix: "")
        }
        let typeCol = dataCols.contains("ZTYPE") ? "d.ZTYPE" : (dataCols.contains("ZUTI") ? "d.ZUTI" : "NULL")
        let order = dataCols.contains("ZINDEX") ? ", d.ZINDEX, d.Z_PK" : ", d.Z_PK"
        return DataJoin(
            typeExpr: typeCol,
            dataExpr: "d.ZDATA",
            clause: "LEFT JOIN ZPASTEBOARDDATA d ON d.ZCLIP = c.Z_PK",
            orderSuffix: order
        )
    }

    private static func makeCollectionJoin(
        tables: Set<String>,
        clipCols: Set<String>,
        db: OpaquePointer
    )
    -> (expr: String, clause: String) {
        let board = joinInfo(
            CollectionTarget(table: "ZPASTEBOARD", alias: "p", foreignKey: "ZPASTEBOARD"),
            tables: tables, clipCols: clipCols, db: db
        )
        let folder = joinInfo(
            CollectionTarget(table: "ZFOLDER", alias: "f", foreignKey: "ZFOLDER"),
            tables: tables, clipCols: clipCols, db: db
        )
        let expr: String = switch (board.expr, folder.expr) {
        case let (.some(b), .some(f)): "COALESCE(NULLIF(\(b), ''), \(f))"
        case let (.some(b), nil): b
        case let (nil, .some(f)): f
        case (nil, nil): "NULL"
        }
        return (expr, [board.clause, folder.clause].compactMap(\.self).joined(separator: "\n"))
    }

    private static func joinInfo(
        _ target: CollectionTarget,
        tables: Set<String>,
        clipCols: Set<String>,
        db: OpaquePointer
    )
    -> (expr: String?, clause: String?) {
        guard tables.contains(target.table), clipCols.contains(target.foreignKey) else { return (nil, nil) }
        let cols = ClipboardAppLibraryReader.columnNames(of: target.table, in: db)
        guard let nameCol = cols.contains("ZNAME") ? "ZNAME" : (cols.contains("ZTITLE") ? "ZTITLE" : nil) else {
            return (nil, nil)
        }
        let smartCol = ["ZISPREDICATE", "ZISSMART", "ZSMART"].first { cols.contains($0) }
        let smartFilter = smartCol.map { " AND COALESCE(\(target.alias).\($0), 0) = 0" } ?? ""
        let clause = """
        LEFT JOIN \(target.table) \(target.alias) ON \(target.alias).Z_PK = c.\(target.foreignKey)\(smartFilter) \
        AND COALESCE(\(target.alias).\(nameCol), '') NOT IN ('', 'All', 'Clipboard', 'Clipboard History', 'History')
        """
        return ("\(target.alias).\(nameCol)", clause)
    }

    private static func collectRecords(
        from rows: OpaquePointer,
        externalFolder: URL
    ) throws
    -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
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
                    pinboard: Reader.text(rows, 10).flatMap { $0.isEmpty ? nil : $0 },
                    title: Reader.text(rows, 1).flatMap { $0.isEmpty ? nil : $0 },
                    time: sqlite3_column_double(rows, 2),
                    bundleID: Reader.text(rows, 3).flatMap { $0.isEmpty ? nil : $0 },
                    fallback: fallbackRepresentation(from: rows, externalFolder: externalFolder)
                )
            }
            if let type = Reader.text(rows, 4),
               let data = Reader.blob(rows, 5, externalFolder: externalFolder),
               !data.isEmpty
            {
                items[key]?.reps.append(.init(uti: type, dataBase64: data.base64EncodedString()))
            }
        }
        guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
        return buildLibrary(order: order, items: items)
    }

    private static func fallbackRepresentation(
        from rows: OpaquePointer,
        externalFolder: URL
    )
    -> PasteImportRecord.Representation? {
        typealias Reader = ClipboardAppLibraryReader
        if let rawData = Reader.blob(rows, 6, externalFolder: externalFolder), !rawData.isEmpty {
            let uti = Reader.text(rows, 7).flatMap { $0.isEmpty ? nil : $0 }
                ?? Reader.imageUTI(forBytes: rawData)
                ?? (String(data: rawData, encoding: .utf8) != nil ? "public.utf8-plain-text" : nil)
            if let uti { return .init(uti: uti, dataBase64: rawData.base64EncodedString()) }
        }
        if let plain = Reader.text(rows, 8), !plain.isEmpty {
            return .init(uti: "public.utf8-plain-text", dataBase64: Data(plain.utf8).base64EncodedString())
        }
        if let search = Reader.text(rows, 9), !search.isEmpty {
            return .init(uti: "public.utf8-plain-text", dataBase64: Data(search.utf8).base64EncodedString())
        }
        return nil
    }

    private static func buildLibrary(order: [Int64], items: [Int64: PendingItem]) -> ClipboardAppLibrary {
        var records: [PasteImportRecord] = []
        var skipped = 0
        for key in order {
            guard let item = items[key] else { continue }
            let reps = item.reps.isEmpty ? (item.fallback.map { [$0] } ?? []) : item.reps
            guard !reps.isEmpty else {
                skipped += 1
                continue
            }
            records.append(PasteImportRecord(
                pinboard: item.pinboard,
                title: item.title,
                timestamp: ClipboardAppLibraryReader.date(from: item.time),
                sourceBundleID: item.bundleID,
                representations: reps
            ))
        }
        return ClipboardAppLibrary(records: records, skipped: skipped)
    }

    private struct PendingItem {
        var pinboard: String?
        var title: String?
        var time: Double
        var bundleID: String?
        var fallback: PasteImportRecord.Representation?
        var reps: [PasteImportRecord.Representation] = []
    }
}
#endif
