// SPDX-License-Identifier: MIT
#if os(macOS)
import Compression
import Foundation
import SQLite3

/// PasteNow stores clips in an SQLite database (`PasteNow.sqlite`), with LZFSE-compressed pasteboard plists in
/// `ZPASTEITEMDATA` (and Core Data external files under `.PasteNow_SUPPORT/_EXTERNAL_DATA/`).
public enum PasteNowLibraryReader {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Group Containers/KAQ3M6FSM7.app.pastenow.PasteNow/Documents/PasteNow.sqlite"
        )
    }

    public static func read(databaseAt url: URL) throws -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        return try Reader.withCopy(of: url, named: url.lastPathComponent) { db, externalFolder in
            guard Reader.hasTables(db, ["ZPASTEITEM"]) else {
                throw Reader.ReadError.notRecognized
            }
            let query = try makeQuery(in: db)
            let rows = try Reader.prepare(db, query)
            defer { sqlite3_finalize(rows) }
            return try collectRecords(from: rows, externalFolder: externalFolder)
        }
    }

    private static func makeQuery(in db: OpaquePointer) throws -> String {
        typealias Reader = ClipboardAppLibraryReader
        let tables = Reader.tableNames(in: db)
        let itemCols = Reader.columnNames(of: "ZPASTEITEM", in: db)
        guard itemCols.contains("Z_PK") else { throw Reader.ReadError.notRecognized }
        let titleExpr = itemCols.contains("ZTITLE") ? "i.ZTITLE" : "NULL"
        let textExpr = itemCols.contains("ZTEXT") ? "i.ZTEXT" : "NULL"
        let timeExpr = itemCols.contains("ZTIMESTAMP")
            ? "i.ZTIMESTAMP"
            : (itemCols.contains("ZUPDATEDATE") ? "i.ZUPDATEDATE" : "0")
        let orderTime = itemCols.contains("ZTIMESTAMP")
            ? "i.ZTIMESTAMP, "
            : (itemCols.contains("ZUPDATEDATE") ? "i.ZUPDATEDATE, " : "")
        let rtfExpr = itemCols.contains("ZRTFDATA") ? "i.ZRTFDATA" : "NULL"
        let urlExpr = itemCols.contains("ZURLDATA") ? "i.ZURLDATA" : "NULL"
        let baseUTIExpr = itemCols.contains("ZBASEUNIFORMTYPE") ? "i.ZBASEUNIFORMTYPE" : "NULL"
        let secondaryUTIExpr = itemCols.contains("ZSECONDARYUNIFORMTYPE") ? "i.ZSECONDARYUNIFORMTYPE" : "NULL"
        let thumbExpr = itemCols.contains("ZTHUMBNAILIMAGE") ? "i.ZTHUMBNAILIMAGE" : "NULL"

        let appJoin = makeAppJoin(tables: tables, itemCols: itemCols, db: db)
        let listJoin = makeListJoin(tables: tables, itemCols: itemCols, db: db)
        let dataJoin = makeDataJoin(tables: tables, itemCols: itemCols, db: db)

        return """
        SELECT i.Z_PK, \(titleExpr), \(textExpr), \(timeExpr), \(appJoin.expr),
               \(rtfExpr), \(urlExpr), \(listJoin.expr), \(baseUTIExpr), \(secondaryUTIExpr),
               \(thumbExpr), \(dataJoin.compressedExpr), \(dataJoin.dataExpr)
        FROM ZPASTEITEM i
        \(appJoin.clause)
        \(listJoin.clause)
        \(dataJoin.clause)
        ORDER BY \(orderTime)i.Z_PK
        LIMIT \(Reader.maxRecords + 1)
        """
    }

    private static func makeAppJoin(
        tables: Set<String>,
        itemCols: Set<String>,
        db: OpaquePointer
    )
    -> (expr: String, clause: String) {
        let hasDirect = itemCols.contains("ZAPPBUNDLEID")
        if tables.contains("ZAPPLICATION"), itemCols.contains("ZAPP") {
            let appCols = ClipboardAppLibraryReader.columnNames(of: "ZAPPLICATION", in: db)
            if appCols.contains("ZBUNDLEID") {
                let expr = hasDirect ? "COALESCE(NULLIF(i.ZAPPBUNDLEID, ''), a.ZBUNDLEID)" : "a.ZBUNDLEID"
                return (expr, "LEFT JOIN ZAPPLICATION a ON a.Z_PK = i.ZAPP")
            }
        }
        return (hasDirect ? "i.ZAPPBUNDLEID" : "NULL", "")
    }

    private static func makeListJoin(
        tables: Set<String>,
        itemCols: Set<String>,
        db: OpaquePointer
    )
    -> (expr: String, clause: String) {
        guard tables.contains("ZPASTELIST"), itemCols.contains("ZLIST") else { return ("NULL", "") }
        let listCols = ClipboardAppLibraryReader.columnNames(of: "ZPASTELIST", in: db)
        guard listCols.contains("ZNAME") else { return ("NULL", "") }
        let typeFilter = listCols.contains("ZLISTTYPE") ? " AND COALESCE(l.ZLISTTYPE, 0) = 0" : ""
        return ("l.ZNAME", "LEFT JOIN ZPASTELIST l ON l.Z_PK = i.ZLIST\(typeFilter)")
    }

    private struct DataJoin {
        let compressedExpr: String
        let dataExpr: String
        let clause: String
    }

    private static func makeDataJoin(
        tables: Set<String>,
        itemCols: Set<String>,
        db: OpaquePointer
    )
    -> DataJoin {
        guard tables.contains("ZPASTEITEMDATA") else {
            return DataJoin(compressedExpr: "0", dataExpr: "NULL", clause: "")
        }
        let dataCols = ClipboardAppLibraryReader.columnNames(of: "ZPASTEITEMDATA", in: db)
        guard dataCols.contains("ZDATA") else {
            return DataJoin(compressedExpr: "0", dataExpr: "NULL", clause: "")
        }
        let compressed = dataCols.contains("ZCOMPRESSED") ? "COALESCE(d.ZCOMPRESSED, 0)" : "0"
        let clause = if itemCols.contains("ZITEMDATA"), dataCols.contains("ZPASTEITEM") {
            "LEFT JOIN ZPASTEITEMDATA d ON d.Z_PK = i.ZITEMDATA OR (i.ZITEMDATA IS NULL AND d.ZPASTEITEM = i.Z_PK)"
        } else if itemCols.contains("ZITEMDATA") {
            "LEFT JOIN ZPASTEITEMDATA d ON d.Z_PK = i.ZITEMDATA"
        } else if dataCols.contains("ZPASTEITEM") {
            "LEFT JOIN ZPASTEITEMDATA d ON d.ZPASTEITEM = i.Z_PK"
        } else {
            ""
        }
        guard !clause.isEmpty else { return DataJoin(compressedExpr: "0", dataExpr: "NULL", clause: "") }
        return DataJoin(compressedExpr: compressed, dataExpr: "d.ZDATA", clause: clause)
    }

    private static func collectRecords(
        from rows: OpaquePointer,
        externalFolder: URL
    ) throws
    -> ClipboardAppLibrary {
        typealias Reader = ClipboardAppLibraryReader
        var records: [PasteImportRecord] = []
        var skipped = 0
        var seen = 0
        var status = sqlite3_step(rows)
        while status == SQLITE_ROW {
            defer { status = sqlite3_step(rows) }
            seen += 1
            guard seen <= Reader.maxRecords else { throw Reader.ReadError.tooLarge }
            guard let record = record(from: rows, externalFolder: externalFolder) else {
                skipped += 1
                continue
            }
            records.append(record)
        }
        guard status == SQLITE_DONE else { throw Reader.ReadError.unreadable }
        return ClipboardAppLibrary(records: records, skipped: skipped)
    }

    private static func record(from rows: OpaquePointer, externalFolder: URL) -> PasteImportRecord? {
        typealias Reader = ClipboardAppLibraryReader
        var reps = representationsFromItemData(rows: rows, externalFolder: externalFolder)
        appendColumnRepresentations(rows: rows, externalFolder: externalFolder, into: &reps)
        if reps.isEmpty,
           let thumb = Reader.blob(rows, 10, externalFolder: externalFolder), !thumb.isEmpty
        {
            let uti = Reader.imageUTI(forBytes: thumb) ?? validImageUTI(Reader.text(rows, 9)) ?? "public.png"
            reps.append(.init(uti: uti, dataBase64: thumb.base64EncodedString()))
        }
        guard !reps.isEmpty else { return nil }
        let listName = Reader.text(rows, 7)
        let pinboard = (listName != nil && listName != "All" && !(listName?.isEmpty ?? true)) ? listName : nil
        let title = Reader.text(rows, 1).flatMap { $0.isEmpty ? nil : $0 }
        return PasteImportRecord(
            pinboard: pinboard,
            title: title,
            timestamp: Reader.date(from: sqlite3_column_double(rows, 3)),
            sourceBundleID: Reader.text(rows, 4).flatMap { $0.isEmpty ? nil : $0 },
            representations: reps
        )
    }

    private static func representationsFromItemData(
        rows: OpaquePointer,
        externalFolder: URL
    )
    -> [PasteImportRecord.Representation] {
        typealias Reader = ClipboardAppLibraryReader
        guard let rawPayload = Reader.blob(rows, 12, externalFolder: externalFolder), !rawPayload.isEmpty else {
            return []
        }
        let isCompressed = sqlite3_column_int(rows, 11) == 1
        let plistData: Data
        if isCompressed {
            guard let decompressed = decompressLZFSE(rawPayload, limit: Reader.maxValueBytes) else { return [] }
            plistData = decompressed
        } else {
            plistData = rawPayload
        }
        guard let items = (try? PropertyListSerialization.propertyList(
            from: plistData, options: [], format: nil
        )) as? [[String: Any]] else { return [] }
        return items.compactMap { entry in
            guard let uti = entry["type"] as? String, !uti.isEmpty,
                  let data = entry["data"] as? Data, !data.isEmpty, data.count <= Reader.maxValueBytes else
            {
                return nil
            }
            return .init(uti: uti, dataBase64: data.base64EncodedString())
        }
    }

    private static func appendColumnRepresentations(
        rows: OpaquePointer,
        externalFolder: URL,
        into reps: inout [PasteImportRecord.Representation]
    ) {
        typealias Reader = ClipboardAppLibraryReader
        let existing = Set(reps.map(\.uti))
        let baseType = Reader.text(rows, 8)
        if let text = Reader.text(rows, 2), !text.isEmpty {
            if baseType == "public.file-url", text.hasPrefix("/") || text.hasPrefix("file://") {
                let urlString = text.hasPrefix("file://") ? text : URL(fileURLWithPath: text).absoluteString
                let rep = PasteImportRecord.Representation(
                    uti: "public.file-url", dataBase64: Data(urlString.utf8).base64EncodedString()
                )
                if let index = reps.firstIndex(where: { $0.uti == "public.file-url" }) {
                    let current = Data(base64Encoded: reps[index].dataBase64)
                        .flatMap { String(data: $0, encoding: .utf8) }
                    if current?.hasPrefix("file:///.file/") == true { reps[index] = rep }
                } else {
                    reps.append(rep)
                }
            } else if baseType != "public.file-url", !existing.contains("public.utf8-plain-text") {
                reps.append(.init(uti: "public.utf8-plain-text", dataBase64: Data(text.utf8).base64EncodedString()))
            }
        }
        if !existing.contains("public.rtf"),
           let rtf = Reader.blob(rows, 5, externalFolder: externalFolder), !rtf.isEmpty
        {
            reps.append(.init(uti: "public.rtf", dataBase64: rtf.base64EncodedString()))
        }
        if !existing.contains("public.url"),
           let urlData = Reader.blob(rows, 6, externalFolder: externalFolder), !urlData.isEmpty
        {
            reps.append(.init(uti: "public.url", dataBase64: urlData.base64EncodedString()))
        }
    }

    private static func validImageUTI(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let known: Set = [
            "public.png", "public.jpeg", "public.tiff", "public.heic", "com.compuserve.gif", "public.gif", "public.webp"
        ]
        return known.contains(candidate) ? candidate : nil
    }

    static func decompressLZFSE(_ input: Data, limit: Int = ClipboardAppLibraryReader.maxValueBytes) -> Data? {
        guard !input.isEmpty else { return nil }
        let chunkSize = 65_536
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { dstBuffer.deallocate() }
        return input.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var stream = compression_stream(
                dst_ptr: dstBuffer, dst_size: 0, src_ptr: srcBase, src_size: 0, state: nil
            )
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZFSE)
                == COMPRESSION_STATUS_OK else { return nil }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = srcBase
            stream.src_size = input.count
            var output = Data()
            while true {
                let remaining = stream.src_size
                stream.dst_ptr = dstBuffer
                stream.dst_size = chunkSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunkSize - stream.dst_size
                guard output.count + produced <= limit else { return nil }
                if produced > 0 { output.append(dstBuffer, count: produced) }
                if status == COMPRESSION_STATUS_END { return output }
                guard status == COMPRESSION_STATUS_OK, produced > 0 || stream.src_size < remaining else { return nil }
            }
        }
    }
}
#endif
