// SPDX-License-Identifier: MIT
import Foundation
import SQLite3

/// A read-only copy of a Paste library that is read in pieces: first only each clip's size and date, to plan the
/// import (`plan`), then the clips themselves a few at a time (`records`). Nothing of the library is held in memory
/// between calls, so a library of any size costs one batch. The copy sits in a temporary folder until `discard()` or
/// the end of the snapshot, and the original is never opened for writing (ADR 0011, ADR 0032).
public actor PasteLibrarySnapshot {
    public struct Batch: Sendable {
        public let records: [PasteImportRecord]
        public let undecodable: Int
    }

    public static let batchRecords = 64
    public static let batchBytes = 16_000_000

    private static let folderPrefix = "pesto-paste-"
    private static let staleAfter: TimeInterval = 86_400

    private let folder: URL
    private var isDiscarded = false
    private let join: PasteLibraryReader.JoinTable

    private init(folder: URL, join: PasteLibraryReader.JoinTable) {
        self.folder = folder
        self.join = join
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    public static func open(
        databaseAt url: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws
    -> PasteLibrarySnapshot {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { throw PasteLibraryReader.ReadError.notFound }
        let suffixes = ["-wal", "-shm"].filter { fileManager.fileExists(atPath: url.path + $0) }
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int else {
            throw PasteLibraryReader.ReadError.unreadable
        }
        removeStaleFolders(in: temporaryDirectory, fileManager: fileManager)
        try requireSpace(
            for: size + suffixes.reduce(0) { $0 + fileSize(URL(fileURLWithPath: url.path + $1), fileManager) },
            in: temporaryDirectory
        )

        let folder = temporaryDirectory.appendingPathComponent("\(folderPrefix)\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let copy = folder.appendingPathComponent("Paste.db")
        do {
            try fileManager.copyItem(at: url, to: copy)
            for suffix in suffixes {
                try fileManager.copyItem(
                    at: URL(fileURLWithPath: url.path + suffix), to: URL(fileURLWithPath: copy.path + suffix)
                )
            }
        } catch {
            try? fileManager.removeItem(at: folder)
            throw PasteLibraryReader.ReadError.unreadable
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            try? fileManager.removeItem(at: folder)
            throw PasteLibraryReader.ReadError.unreadable
        }
        defer { sqlite3_close(db) }
        guard let join = PasteLibraryReader.joinTable(in: db) else {
            try? fileManager.removeItem(at: folder)
            throw PasteLibraryReader.ReadError.notAPasteLibrary
        }
        return PasteLibrarySnapshot(folder: folder, join: join)
    }

    public func discard() {
        isDiscarded = true
        try? FileManager.default.removeItem(at: folder)
    }

    /// The copy is opened for each call and closed after it, so the actor holds no database handle between calls.
    private func connect() throws -> OpaquePointer {
        var handle: OpaquePointer?
        guard !isDiscarded, sqlite3_open_v2(
            folder.appendingPathComponent("Paste.db").path, &handle, SQLITE_OPEN_READONLY, nil
        ) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw PasteLibraryReader.ReadError.unreadable
        }
        return db
    }

    /// Reads each clip's size and date, pinboards first and then history newest first, and returns the clips the cap
    /// and the retention setting leave room for. Only small columns are read: `length()` of a payload does not load it.
    public func plan(
        cap: ImportCap = .paste,
        retention: RetentionPolicy,
        existing: [ExistingClip] = [],
        now: Date = .now
    ) throws
    -> PasteImportPlan {
        let db = try connect()
        defer { sqlite3_close(db) }
        var planner = PasteImportPlanner(cap: cap)
        try Self.rows(in: db, sql: metadataQuery(history: false)) { planner.addPinboard($0) }
        try Self.rows(in: db, sql: metadataQuery(history: true)) { planner.addHistory($0) }
        return planner.plan(retention: retention, existing: existing, now: now)
    }

    /// The clips of `entries`, in order. A clip whose payload is not a Paste archive is counted, not returned.
    public func records(for entries: ArraySlice<PasteImportPlan.Entry>) throws -> Batch {
        let db = try connect()
        defer { sqlite3_close(db) }
        let query = """
        SELECT s.ZTITLE, a.ZBUNDLEIDENTIFIER, d.ZPASTEBOARDITEMS
        FROM ZSNIPPET s
        LEFT JOIN ZAPPLICATION a ON a.Z_PK = s.ZSOURCEAPPLICATION
        LEFT JOIN ZSNIPPETDATA d ON d.Z_PK = ?2
        WHERE s.Z_PK = ?1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let rows = statement else {
            throw PasteLibraryReader.ReadError.notAPasteLibrary
        }
        defer { sqlite3_finalize(rows) }
        var records: [PasteImportRecord] = []
        var undecodable = 0
        for entry in entries {
            sqlite3_reset(rows)
            sqlite3_bind_int64(rows, 1, entry.snippetKey)
            sqlite3_bind_int64(rows, 2, entry.dataKey)
            let status = sqlite3_step(rows)
            guard status == SQLITE_ROW || status == SQLITE_DONE else { throw PasteLibraryReader.ReadError.unreadable }
            guard status == SQLITE_ROW else {
                undecodable += 1
                continue
            }
            // Unarchiving makes Foundation objects that are only released when an autorelease pool drains, and a loop
            // inside one task never drains the task's own: a pool per clip keeps the peak to one group.
            let decoded = autoreleasepool { () -> [PasteImportRecord.Representation]? in
                guard let blob = PasteLibraryReader.blob(rows, 2),
                      blob.count <= PasteLibraryReader.maxRecordBytes else { return nil }
                return PasteArchiveDecoder.representations(in: blob)
            }
            guard let representations = decoded else {
                undecodable += 1
                continue
            }
            records.append(PasteImportRecord(
                pinboard: entry.pinboard,
                title: PasteLibraryReader.text(rows, 0).flatMap { $0.isEmpty ? nil : $0 },
                timestamp: entry.timestamp,
                sourceBundleID: PasteLibraryReader.text(rows, 1),
                representations: representations
            ))
        }
        return Batch(records: records, undecodable: undecodable)
    }

    private func metadataQuery(history: Bool) -> String {
        let isHistory = "COALESCE(l.Z_ENT = (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'PasteboardHistory'), 0)"
        let order = history
            ? "ORDER BY COALESCE(s.ZCREATEDAT, s.ZTIMESTAMP) DESC, s.Z_PK DESC"
            : "ORDER BY l.ZDISPLAYORDER, s.ZDISPLAYORDERINPINBOARD, s.Z_PK"
        return """
        SELECT s.Z_PK, d.Z_PK, length(d.ZPASTEBOARDITEMS), COALESCE(s.ZCREATEDAT, s.ZTIMESTAMP), l.ZNAME
        FROM ZSNIPPETLIST l
        JOIN \(join.table) j ON j.\(join.lists) = l.Z_PK
        JOIN ZSNIPPET s ON s.Z_PK = j.\(join.snippets)
        LEFT JOIN ZSNIPPETDATA d ON d.ZSNIPPET = s.Z_PK
        WHERE \(isHistory) = \(history ? 1 : 0)
        \(order)
        """
    }

    private static func rows(
        in db: OpaquePointer, sql: String, _ body: (PasteImportPlanner.Row) -> Void
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let rows = statement else {
            throw PasteLibraryReader.ReadError.notAPasteLibrary
        }
        defer { sqlite3_finalize(rows) }
        var status = sqlite3_step(rows)
        while status == SQLITE_ROW {
            let hasData = sqlite3_column_type(rows, 1) != SQLITE_NULL
            let hasLength = sqlite3_column_type(rows, 2) != SQLITE_NULL
            body(PasteImportPlanner.Row(
                snippetKey: sqlite3_column_int64(rows, 0),
                dataKey: hasData ? sqlite3_column_int64(rows, 1) : nil,
                bytes: hasLength ? Int(sqlite3_column_int64(rows, 2)) : nil,
                timestamp: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(rows, 3)),
                pinboard: PasteLibraryReader.text(rows, 4) ?? "Imported from Paste"
            ))
            status = sqlite3_step(rows)
        }
        // The loop also ends on an error (a damaged page, a busy file), and a library that is merely short must not be
        // reported as the whole library.
        guard status == SQLITE_DONE else { throw PasteLibraryReader.ReadError.unreadable }
    }

    private static func fileSize(_ url: URL, _ fileManager: FileManager) -> Int {
        ((try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
    }

    private static func requireSpace(for bytes: Int, in directory: URL) throws {
        let key = URLResourceKey.volumeAvailableCapacityForImportantUsageKey
        guard let free = (try? directory.resourceValues(forKeys: [key]))?
            .volumeAvailableCapacityForImportantUsage else { return }
        if free < Int64(bytes) + 100_000_000 { throw PasteLibraryReader.ReadError.notEnoughSpace }
    }

    /// A copy left behind by a Pesto that quit or crashed during an import. A day is far longer than any import.
    static func removeStaleFolders(in directory: URL, fileManager: FileManager, now: Date = .now) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(folderPrefix) {
            let url = directory.appendingPathComponent(name)
            let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            if let modified, now.timeIntervalSince(modified) > staleAfter { try? fileManager.removeItem(at: url) }
        }
    }
}
