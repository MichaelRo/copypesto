// SPDX-License-Identifier: MIT
#if os(macOS)
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
        let dbDir = url.deletingLastPathComponent()
        return try Reader.withCopy(of: url, named: url.lastPathComponent) { db, externalFolder in
            let tables = Reader.tableNames(in: db)
            if tables.contains("ZCDCLIPBOARDITEM") {
                return try readModern(db: db, tables: tables, dbDir: dbDir, externalFolder: externalFolder)
            }
            if tables.contains("ZPASTEDITEM") {
                return try readLegacy(db: db)
            }
            throw Reader.ReadError.notRecognized
        }
    }

    private static func readModern(
        db: OpaquePointer,
        tables: Set<String>,
        dbDir: URL,
        externalFolder: URL
    ) throws
    -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        let cols = Reader.columnNames(of: "ZCDCLIPBOARDITEM", in: db)
        guard cols.contains("Z_PK") else { throw Reader.ReadError.notRecognized }
        let query = makeModernQuery(cols: cols, tables: tables, db: db)
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
            guard let record = modernRecord(from: rows, dbDir: dbDir, externalFolder: externalFolder) else {
                skipped += 1
                continue
            }
            records.append(record)
        }
        guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
        return ClipboardAppLibrary(records: records, skipped: skipped)
    }

    private static func makeModernQuery(
        cols: Set<String>,
        tables: Set<String>,
        db: OpaquePointer
    )
    -> String {
        typealias Reader = ClipboardAppLibraryReader
        func col(_ name: String) -> String {
            cols.contains(name) ? "i.\(name)" : "NULL"
        }
        let createdExpr = cols.contains("ZCREATEDAT") ? "i.ZCREATEDAT" : "0"
        let orderClause = cols.contains("ZCREATEDAT") ? "ORDER BY i.ZCREATEDAT, i.Z_PK" : "ORDER BY i.Z_PK"
        let whereClause = cols.contains("ZMARKEDDELETE") ? "WHERE COALESCE(i.ZMARKEDDELETE, 0) = 0" : ""

        let blobJoin = makeBlobJoin(cols: cols, tables: tables, db: db)
        let colJoin = makeCollectionJoin(cols: cols, tables: tables, db: db)

        return """
        SELECT \(col("ZSTRING")), \(createdExpr), \(col("ZAPPBUNDLEID")),
               \(cols.contains("ZISPINNED") ? "i.ZISPINNED" : "0"),
               \(col("ZNAME")), \(col("ZPBTYPE")), \(col("ZITEMTYPE")),
               \(col("ZCONTENTFILEURL")), \(col("ZCONTENTIMAGEFILEURL")),
               \(col("ZCONTENTLINKURL")), \(col("ZCONTENTRICHTEXTDATA")),
               \(blobJoin.expr), \(colJoin.expr)
        FROM ZCDCLIPBOARDITEM i
        \(blobJoin.clause)
        \(colJoin.clause)
        \(whereClause)
        \(orderClause)
        LIMIT \(Reader.maxRecords + 1)
        """
    }

    private static func makeBlobJoin(
        cols: Set<String>,
        tables: Set<String>,
        db: OpaquePointer
    )
    -> (expr: String, clause: String) {
        guard tables.contains("ZCDBLOB") else { return ("NULL", "") }
        let blobCols = ClipboardAppLibraryReader.columnNames(of: "ZCDBLOB", in: db)
        guard blobCols.contains("ZDATA") else { return ("NULL", "") }
        if cols.contains("ZBLOB"), blobCols.contains("ZITEM") {
            return ("b.ZDATA", "LEFT JOIN ZCDBLOB b ON b.Z_PK = i.ZBLOB OR (i.ZBLOB IS NULL AND b.ZITEM = i.Z_PK)")
        }
        if cols.contains("ZBLOB") {
            return ("b.ZDATA", "LEFT JOIN ZCDBLOB b ON b.Z_PK = i.ZBLOB")
        }
        if blobCols.contains("ZITEM") {
            return ("b.ZDATA", "LEFT JOIN ZCDBLOB b ON b.ZITEM = i.Z_PK")
        }
        return ("NULL", "")
    }

    private static func makeCollectionJoin(
        cols: Set<String>,
        tables: Set<String>,
        db: OpaquePointer
    )
    -> (expr: String, clause: String) {
        guard tables.contains("ZCDCOLLECTION"), cols.contains("ZCOLLECTIONID") else { return ("NULL", "") }
        let colCols = ClipboardAppLibraryReader.columnNames(of: "ZCDCOLLECTION", in: db)
        guard colCols.contains("ZID"), colCols.contains("ZNAME") else { return ("NULL", "") }
        return ("c.ZNAME", "LEFT JOIN ZCDCOLLECTION c ON c.ZID = i.ZCOLLECTIONID")
    }

    private static func modernRecord(
        from rows: OpaquePointer,
        dbDir: URL,
        externalFolder: URL
    )
    -> PasteImportRecord? {
        typealias Reader = ClipboardAppLibraryReader
        var reps: [PasteImportRecord.Representation] = []
        var seenUTIs = Set<String>()
        func add(_ uti: String, _ data: Data) {
            guard !data.isEmpty, data.count <= Reader.maxValueBytes, seenUTIs.insert(uti).inserted else { return }
            reps.append(.init(uti: uti, dataBase64: data.base64EncodedString()))
        }

        if let blobData = Reader.blob(rows, 11, externalFolder: externalFolder), !blobData.isEmpty {
            let uti = blobUTI(data: blobData, pbType: Reader.text(rows, 5), itemType: Reader.text(rows, 6))
            if let uti { add(uti, blobData) }
        }
        if let imagePath = Reader.text(rows, 8),
           let image = readSafeImage(imagePath, dbDir: dbDir)
        {
            add(image.uti, image.data)
        }
        if let fileRaw = Reader.text(rows, 7), let fileURL = normalizedFileURL(fileRaw) {
            add("public.file-url", Data(fileURL.utf8))
        }
        if let linkRaw = Reader.text(rows, 9), !linkRaw.isEmpty {
            add("public.url", Data(linkRaw.utf8))
        }
        if let rtfData = Reader.blob(rows, 10, externalFolder: externalFolder), !rtfData.isEmpty {
            add("public.rtf", rtfData)
        }
        if let text = Reader.text(rows, 0), !text.isEmpty {
            add("public.utf8-plain-text", Data(text.utf8))
        }
        guard !reps.isEmpty else { return nil }

        let collectionName = Reader.text(rows, 12).flatMap { $0.isEmpty ? nil : $0 }
        let isPinned = sqlite3_column_int(rows, 3) != 0
        return PasteImportRecord(
            pinboard: collectionName ?? (isPinned ? "Pinned in PastePal" : nil),
            title: Reader.text(rows, 4).flatMap { $0.isEmpty ? nil : $0 },
            timestamp: Reader.date(from: sqlite3_column_double(rows, 1)),
            sourceBundleID: Reader.text(rows, 2).flatMap { $0.isEmpty ? nil : $0 },
            representations: reps
        )
    }

    private static func blobUTI(data: Data, pbType: String?, itemType: String?) -> String? {
        if let detected = ClipboardAppLibraryReader.imageUTI(forBytes: data) { return detected }
        if let pbType, !pbType.isEmpty, pbType.contains(".") { return pbType }
        if itemType?.lowercased() == "image" { return "public.png" }
        if String(data: data, encoding: .utf8) != nil { return "public.utf8-plain-text" }
        return nil
    }

    private static func readSafeImage(_ rawPath: String, dbDir: URL) -> (uti: String, data: Data)? {
        typealias Reader = ClipboardAppLibraryReader
        guard !rawPath.isEmpty, !rawPath.contains("\0"), !rawPath.contains("\\"), !rawPath.contains("..") else {
            return nil
        }
        let components: [String]?
        let ext: String
        if rawPath.hasPrefix("file://") {
            guard let parsed = URL(string: rawPath), parsed.isFileURL else { return nil }
            ext = parsed.pathExtension
            components = relativeComponents(of: parsed, inside: dbDir)
        } else if rawPath.hasPrefix("/") {
            let parsed = URL(fileURLWithPath: rawPath)
            ext = parsed.pathExtension
            components = relativeComponents(of: parsed, inside: dbDir)
        } else {
            let parts = rawPath.split(separator: "/").map(String.init)
            ext = (rawPath as NSString).pathExtension
            components = parts.isEmpty ? nil : parts
        }
        guard let components, let uti = Reader.imageUTI(forExtension: ext),
              let data = Reader.readContainedFile(relativeComponents: components, inside: dbDir) else
        {
            return nil
        }
        return (Reader.imageUTI(forBytes: data) ?? uti, data)
    }

    private static func relativeComponents(of fileURL: URL, inside rootDir: URL) -> [String]? {
        let rootPath = rootDir.standardizedFileURL.path
        let targetPath = fileURL.standardizedFileURL.path
        guard targetPath.hasPrefix(rootPath + "/") else { return nil }
        let tail = String(targetPath.dropFirst(rootPath.count + 1))
        let parts = tail.split(separator: "/").map(String.init)
        return parts.isEmpty ? nil : parts
    }

    private static func normalizedFileURL(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("file://") { return raw }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw).absoluteString }
        return nil
    }

    private static func readLegacy(db: OpaquePointer) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        let cols = Reader.columnNames(of: "ZPASTEDITEM", in: db)
        guard cols.contains("Z_PK"), cols.contains("ZTEXT") else { throw Reader.ReadError.notRecognized }
        let dateExpr = cols.contains("ZDATE") ? "ZDATE" : "0"
        let bundleExpr = cols.contains("ZSOURCEAPPBUNDLEIDENTIFIER") ? "ZSOURCEAPPBUNDLEIDENTIFIER" : "NULL"
        let pinExpr = cols.contains("ZISPINNED") ? "ZISPINNED" : "0"
        let orderClause = cols.contains("ZDATE") ? "ORDER BY ZDATE, Z_PK" : "ORDER BY Z_PK"
        let rows = try Reader.prepare(db, """
        SELECT Z_PK, ZTEXT, \(dateExpr), \(bundleExpr), \(pinExpr)
        FROM ZPASTEDITEM \(orderClause) LIMIT \(Reader.maxRecords + 1)
        """)
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
            let isPinned = sqlite3_column_int(rows, 4) != 0
            records.append(PasteImportRecord(
                pinboard: isPinned ? "Pinned in PastePal" : nil,
                title: nil,
                timestamp: Reader.date(from: sqlite3_column_double(rows, 2)),
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
#endif
