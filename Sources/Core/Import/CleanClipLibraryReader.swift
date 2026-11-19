// SPDX-License-Identifier: MIT
#if os(macOS)
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
        let dbDir = url.deletingLastPathComponent()
        return try Reader.withCopy(of: url, named: url.lastPathComponent) { db, externalFolder in
            guard Reader.hasTables(db, ["ZHISTORYITEM", "ZHISTORYITEMCONTENT"]) else {
                throw Reader.ReadError.notRecognized
            }
            let groupNames = readGroupNames(in: db)
            let query = try makeQuery(in: db)
            let rows = try Reader.prepare(db, query)
            defer { sqlite3_finalize(rows) }
            return try collectRecords(
                from: rows, dbDir: dbDir, externalFolder: externalFolder, groupNames: groupNames
            )
        }
    }

    private static func makeQuery(in db: OpaquePointer) throws -> String {
        typealias Reader = ClipboardAppLibraryReader
        let itemCols = Reader.columnNames(of: "ZHISTORYITEM", in: db)
        let contentCols = Reader.columnNames(of: "ZHISTORYITEMCONTENT", in: db)
        guard itemCols.contains("Z_PK"), contentCols.contains("ZITEM"), contentCols.contains("ZTYPE") else {
            throw Reader.ReadError.notRecognized
        }
        let appExpr = itemCols.contains("ZAPPLICATION") ? "i.ZAPPLICATION" : "NULL"
        let timeExpr = switch (itemCols.contains("ZLASTCOPIEDAT"), itemCols.contains("ZFIRSTCOPIEDAT")) {
        case (true, true): "COALESCE(i.ZLASTCOPIEDAT, i.ZFIRSTCOPIEDAT)"
        case (true, false): "i.ZLASTCOPIEDAT"
        case (false, true): "i.ZFIRSTCOPIEDAT"
        case (false, false): "0"
        }
        let orderTime = itemCols.contains("ZLASTCOPIEDAT")
            ? "i.ZLASTCOPIEDAT, "
            : (itemCols.contains("ZFIRSTCOPIEDAT") ? "i.ZFIRSTCOPIEDAT, " : "")
        let pinExpr = itemCols.contains("ZPIN") ? "i.ZPIN" : "NULL"
        let aliasExpr = itemCols.contains("ZALIAS") ? "i.ZALIAS" : "NULL"
        let metaExpr = contentCols.contains("ZMETADATA") ? "c.ZMETADATA" : "NULL"
        let valueExpr = contentCols.contains("ZVALUE") ? "c.ZVALUE" : "NULL"
        let pidExpr = contentCols.contains("ZPERSISTENTID") ? "c.ZPERSISTENTID" : "NULL"
        let previewExpr = contentCols.contains("ZPREVIEWDATA") ? "c.ZPREVIEWDATA" : "NULL"
        return """
        SELECT i.Z_PK, \(appExpr), \(timeExpr), \(pinExpr), \(aliasExpr),
               c.ZTYPE, \(metaExpr), \(valueExpr), \(pidExpr), \(previewExpr)
        FROM ZHISTORYITEM i LEFT JOIN ZHISTORYITEMCONTENT c ON c.ZITEM = i.Z_PK
        ORDER BY \(orderTime)i.Z_PK, c.Z_PK
        """
    }

    private static func readGroupNames(in db: OpaquePointer) -> [Int64: String] {
        typealias Reader = ClipboardAppLibraryReader
        let tables = Reader.tableNames(in: db)
        guard tables.contains("ZGROUPITEM") else { return [:] }
        let groupCols = Reader.columnNames(of: "ZGROUPITEM", in: db)
        guard groupCols.contains("Z_PK"), groupCols.contains("ZNAME") else { return [:] }
        guard let join = groupJoinTable(in: db, tables: tables) else { return [:] }

        let smartClause = groupCols.contains("ZISSMARTLIST") ? "COALESCE(g.ZISSMARTLIST, 0) = 0" : "1 = 1"
        let deletedClause = groupCols.contains("ZSOFTDELETED") ? "COALESCE(g.ZSOFTDELETED, 0) = 0" : "1 = 1"
        let orderClause = groupCols.contains("ZPIN") ? "ORDER BY g.ZPIN, g.Z_PK" : "ORDER BY g.Z_PK"
        let sql = """
        SELECT j.\(join.items), g.ZNAME
        FROM \(join.table) j
        JOIN ZGROUPITEM g ON g.Z_PK = j.\(join.groups)
        WHERE \(smartClause) AND \(deletedClause)
          AND g.ZNAME IS NOT NULL AND g.ZNAME != '' AND g.ZNAME NOT IN ('All', 'Tutorial')
        \(orderClause)
        """
        guard let rows = try? Reader.prepare(db, sql) else { return [:] }
        defer { sqlite3_finalize(rows) }
        var map: [Int64: String] = [:]
        while sqlite3_step(rows) == SQLITE_ROW {
            let itemPK = sqlite3_column_int64(rows, 0)
            if map[itemPK] == nil, let name = Reader.text(rows, 1), !name.isEmpty {
                map[itemPK] = name
            }
        }
        return map
    }

    private struct GroupJoin {
        let table: String
        let groups: String
        let items: String
    }

    private static func groupJoinTable(
        in db: OpaquePointer,
        tables: Set<String>
    )
    -> GroupJoin? {
        typealias Reader = ClipboardAppLibraryReader
        let candidates = tables.filter { $0.range(of: #"^Z_\d+ITEMS$"#, options: .regularExpression) != nil }.sorted()
        for name in candidates {
            let cols = Reader.columnNames(of: name, in: db)
            let groups = cols.first { $0.range(of: #"^Z_\d+GROUPS$"#, options: .regularExpression) != nil }
            let items = cols.first { $0.range(of: #"^Z_\d+ITEMS$"#, options: .regularExpression) != nil }
            if let groups, let items { return GroupJoin(table: name, groups: groups, items: items) }
        }
        return nil
    }

    private static func collectRecords(
        from rows: OpaquePointer,
        dbDir: URL,
        externalFolder: URL,
        groupNames: [Int64: String]
    ) throws
    -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
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
                let alias = Reader.text(rows, 4).flatMap { $0.isEmpty ? nil : $0 }
                items[key] = Pending(
                    app: Reader.text(rows, 1),
                    time: sqlite3_column_double(rows, 2),
                    pinboard: groupNames[key] ?? (isPinned ? "Pinned in CleanClip" : nil),
                    title: alias
                )
            }
            if let rep = representation(from: rows, dbDir: dbDir, externalFolder: externalFolder) {
                items[key]?.representations.append(rep)
            }
        }
        guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
        return buildLibrary(order: order, items: items)
    }

    private static func representation(
        from rows: OpaquePointer,
        dbDir: URL,
        externalFolder: URL
    )
    -> PasteImportRecord.Representation? {
        typealias Reader = ClipboardAppLibraryReader
        let type = Reader.text(rows, 5) ?? "public.utf8-plain-text"
        if let blob = Reader.blob(rows, 7, externalFolder: externalFolder), !blob.isEmpty {
            return .init(uti: type, dataBase64: blob.base64EncodedString())
        }
        if let pid = Reader.text(rows, 8), isValidUUID(pid), isSafeUTI(type),
           let fileData = Reader.readContainedFile(
               relativeComponents: ["PrivateData", "HistoryItemContents", "\(pid).\(type)"],
               inside: dbDir
           )
        {
            return .init(uti: type, dataBase64: fileData.base64EncodedString())
        }
        if let meta = Reader.text(rows, 6), !meta.isEmpty, meta != "\u{FFFC}" {
            return .init(uti: type, dataBase64: Data(meta.utf8).base64EncodedString())
        }
        if let preview = Reader.blob(rows, 9, externalFolder: externalFolder), !preview.isEmpty {
            return .init(uti: "public.jpeg", dataBase64: preview.base64EncodedString())
        }
        return nil
    }

    private static func isValidUUID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isSafeUTI(_ value: String) -> Bool {
        !value.contains("..") && value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func buildLibrary(order: [Int64], items: [Int64: Pending]) -> ClipboardAppLibrary {
        var records: [PasteImportRecord] = []
        var skipped = 0
        for key in order {
            guard let item = items[key], !item.representations.isEmpty else {
                skipped += 1
                continue
            }
            records.append(PasteImportRecord(
                pinboard: item.pinboard,
                title: item.title,
                timestamp: ClipboardAppLibraryReader.date(from: item.time),
                sourceBundleID: item.app,
                representations: item.representations
            ))
        }
        return ClipboardAppLibrary(records: records, skipped: skipped)
    }

    private struct Pending {
        var app: String?
        var time: Double
        var pinboard: String?
        var title: String?
        var representations: [PasteImportRecord.Representation] = []
    }
}
#endif
