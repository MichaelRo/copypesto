// SPDX-License-Identifier: MIT
import Foundation
import SQLite3
import Testing
@testable import PestoCore

@objc(PestoTestFixtureItem)
final class FixtureItem: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool {
        true
    }

    let types: [String]
    let data: [String: Data]

    init(types: [String], data: [String: Data]) {
        self.types = types
        self.data = data
    }

    required init?(coder _: NSCoder) {
        types = []
        data = [:]
    }

    func encode(with coder: NSCoder) {
        coder.encode(types as NSArray, forKey: "types")
        coder.encode(data as NSDictionary, forKey: "data")
    }
}

/// A Paste.db with the real table layout and archive shape, built here so no one's clips are needed.
struct PasteFixture {
    /// Core Data numbers a many-to-many join table from the order of its entities, so it changes with the model.
    struct JoinTable {
        var name = "Z_6LISTS"
        var snippets = "Z_6SNIPPETS"
        var lists = "Z_13LISTS"
    }

    let url: URL
    private let join: JoinTable
    private var db: OpaquePointer?

    init(join: JoinTable = JoinTable()) throws {
        self.join = join
        url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).db")
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw PasteLibraryReader.ReadError.unreadable }
        try run("""
        CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR);
        INSERT INTO Z_PRIMARYKEY VALUES (14, 'PasteboardHistory'), (15, 'Pinboard');
        CREATE TABLE ZSNIPPETLIST (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZDISPLAYORDER INTEGER, ZNAME VARCHAR);
        CREATE TABLE ZSNIPPET (Z_PK INTEGER PRIMARY KEY, ZDISPLAYORDERINPINBOARD INTEGER, ZSOURCEAPPLICATION INTEGER,
            ZCREATEDAT TIMESTAMP, ZTIMESTAMP TIMESTAMP, ZTITLE VARCHAR);
        CREATE TABLE ZSNIPPETDATA (Z_PK INTEGER PRIMARY KEY, ZSNIPPET INTEGER, ZPASTEBOARDITEMS BLOB);
        CREATE TABLE ZAPPLICATION (Z_PK INTEGER PRIMARY KEY, ZBUNDLEIDENTIFIER VARCHAR);
        CREATE TABLE \(join.name) (\(join.snippets) INTEGER, \(join.lists) INTEGER);
        INSERT INTO ZAPPLICATION VALUES (1, 'com.example.editor');
        INSERT INTO ZSNIPPETLIST VALUES (1, 14, 0, 'Clipboard History'), (2, 15, 1, 'Commands'), (3, 15, 2, 'Prompts');
        """)
    }

    static func archive(_ text: String, extraType: String? = nil) throws -> Data {
        NSKeyedArchiver.setClassName("PasteCore.PasteboardItem", for: FixtureItem.self)
        var types = ["public.utf8-plain-text"]
        var data = ["public.utf8-plain-text": Data(text.utf8)]
        if let extraType {
            types.insert(extraType, at: 0)
            data[extraType] = Data("<b>\(text)</b>".utf8)
        }
        let archive = try NSKeyedArchiver.archivedData(
            withRootObject: [FixtureItem(types: types, data: data)] as NSArray, requiringSecureCoding: true
        )
        return Data([0x01]) + archive
    }

    func run(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw PasteLibraryReader.ReadError.unreadable }
    }

    func addSnippet(id: Int, list: Int, title: String?, blob: Data?, seconds: Double = 1000) throws {
        try run(
            "INSERT INTO ZSNIPPET VALUES (\(id), \(id), 1, \(seconds), NULL, \(title.map { "'\($0)'" } ?? "NULL"));"
        )
        try run("INSERT INTO \(join.name) VALUES (\(id), \(list));")
        guard let blob else { return }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(
            db,
            "INSERT INTO ZSNIPPETDATA (ZSNIPPET, ZPASTEBOARDITEMS) VALUES (\(id), ?)",
            -1,
            &statement,
            nil
        )
        blob.withUnsafeBytes { _ = sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(blob.count), nil) }
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    /// `count` snippets with ids from `first` in `list`, one shared payload, `seconds(id)` after the 2001 epoch.
    func addMany(from first: Int, count: Int, list: Int, blob: Data, seconds: (Int) -> Double) throws {
        try run("BEGIN;")
        var snippet: OpaquePointer?
        var payload: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO ZSNIPPET VALUES (?1, ?1, 1, ?2, NULL, NULL)", -1, &snippet, nil)
        sqlite3_prepare_v2(
            db,
            "INSERT INTO ZSNIPPETDATA (ZSNIPPET, ZPASTEBOARDITEMS) VALUES (?1, ?2)",
            -1,
            &payload,
            nil
        )
        for id in first..<(first + count) {
            sqlite3_reset(snippet)
            sqlite3_bind_int(snippet, 1, Int32(id))
            sqlite3_bind_double(snippet, 2, seconds(id))
            sqlite3_step(snippet)
            sqlite3_reset(payload)
            sqlite3_bind_int(payload, 1, Int32(id))
            blob.withUnsafeBytes { _ = sqlite3_bind_blob(payload, 2, $0.baseAddress, Int32(blob.count), nil) }
            sqlite3_step(payload)
        }
        sqlite3_finalize(snippet)
        sqlite3_finalize(payload)
        try run(
            "INSERT INTO \(join.name) SELECT Z_PK, \(list) FROM ZSNIPPET "
                + "WHERE Z_PK >= \(first) AND Z_PK < \(first + count);"
        )
        try run("COMMIT;")
    }

    func close() {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: url)
    }
}

struct EverythingRead {
    let plan: PasteImportPlan
    let records: [PasteImportRecord]
    let undecodable: Int
}

/// Everything a snapshot of `url` offers, read the way the import reads it: plan first, then the clips.
func readEverything(
    _ url: URL,
    cap: ImportCap = .paste,
    retention: RetentionPolicy = RetentionPolicy(maxAge: .infinity, maxItemCount: 1_000_000, maxTotalBytes: .max),
    temporaryDirectory: URL = FileManager.default.temporaryDirectory
) async throws
-> EverythingRead {
    let snapshot = try PasteLibrarySnapshot.open(databaseAt: url, temporaryDirectory: temporaryDirectory)
    let plan = try await snapshot.plan(cap: cap, retention: retention)
    let batch = try await snapshot.records(for: (plan.pinboards + plan.history)[...])
    await snapshot.discard()
    return EverythingRead(plan: plan, records: batch.records, undecodable: batch.undecodable)
}

@Suite("Reading a Paste library")
struct PasteLibraryReaderTests {
    @Test("a library whose join table another version of Paste numbered differently is still read")
    func whenJoinTableHasOtherNumbers_thenStillRead() async throws {
        let fixture = try PasteFixture(join: .init(name: "Z_7LISTS", snippets: "Z_7SNIPPETS", lists: "Z_14LISTS"))
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: "Deploy", blob: PasteFixture.archive("alembic upgrade head"))

        let library = try await readEverything(fixture.url)

        #expect(library.plan.pinboards.first?.pinboard == "Commands")
        #expect(library.records.count == 1)
    }

    @Test("a database with no join table between snippets and lists is not a Paste library")
    func whenNoJoinTable_thenNotAPasteLibrary() throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.run("DROP TABLE Z_6LISTS;")

        #expect(throws: PasteLibraryReader.ReadError.notAPasteLibrary) {
            try PasteLibrarySnapshot.open(databaseAt: fixture.url)
        }
    }

    @Test("the sandbox container of the App Store version is among the places looked in")
    func whenAppStoreVersion_thenItsContainerIsCandidate() {
        let home = URL(fileURLWithPath: "/Users/someone")

        let paths = PasteLibraryReader.candidateDatabaseURLs(homeDirectory: home).map(\.path)

        #expect(paths.contains { $0.contains("Containers/com.wiheads.paste/") })
    }

    @Test("pinboards and history are read apart, in order, with titles, times and source apps")
    func whenLibraryHasBoardsAndHistory_thenSplit() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: "Deploy", blob: PasteFixture.archive("alembic upgrade head"))
        try fixture.addSnippet(
            id: 2, list: 3, title: nil, blob: PasteFixture.archive("Review this", extraType: "public.html")
        )
        try fixture.addSnippet(id: 3, list: 1, title: nil, blob: PasteFixture.archive("from history"), seconds: 5000)

        let library = try await readEverything(fixture.url)

        #expect(library.plan.pinboards.compactMap(\.pinboard) == ["Commands", "Prompts"])
        #expect(library.plan.history.count == 1)
        #expect(library.plan.pinSummary == "Commands (1), Prompts (1)")
        let deploy = try #require(library.records.first)
        #expect(deploy.title == "Deploy")
        #expect(deploy.pinboard == "Commands")
        #expect(deploy.sourceBundleID == "com.example.editor")
        #expect(deploy.timestamp == Date(timeIntervalSinceReferenceDate: 1000))
        let history = try #require(library.records.last)
        #expect(history.pinboard == nil)
        #expect(history.timestamp == Date(timeIntervalSinceReferenceDate: 5000))
    }

    @Test("every representation is kept in Paste's order, so the importer can choose like a live copy does")
    func whenItemHasSeveralTypes_thenAllKeptInOrder() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: nil, blob: PasteFixture.archive("hi", extraType: "public.html"))

        let record = try #require(await readEverything(fixture.url).records.first)

        #expect(record.representations.map(\.uti) == ["public.html", "public.utf8-plain-text"])
        #expect(Data(base64Encoded: record.representations[1].dataBase64) == Data("hi".utf8))
    }

    @Test("a snippet with no payload is counted as unusable, and one that is not an archive as undecodable")
    func whenPayloadIsGarbageOrMissing_thenCountedNotFatal() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: nil, blob: Data([1, 2, 3, 4]))
        try fixture.addSnippet(id: 2, list: 2, title: nil, blob: nil)
        try fixture.addSnippet(id: 3, list: 2, title: nil, blob: PasteFixture.archive("kept"))

        let library = try await readEverything(fixture.url)

        #expect(library.plan.unusable == 1)
        #expect(library.records.count == 1 && library.undecodable == 1)
        #expect(library.plan.libraryClips == 3)
    }

    @Test("history is newest first, ties go to the later row, and pinboards keep Paste's board and in-board order")
    func whenOrdered_thenNewestFirstAndBoardsInOrder() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        let blob = try PasteFixture.archive("x")
        try fixture.addSnippet(id: 1, list: 1, title: nil, blob: blob, seconds: 100)
        try fixture.addSnippet(id: 2, list: 1, title: nil, blob: blob, seconds: 300)
        try fixture.addSnippet(id: 3, list: 1, title: nil, blob: blob, seconds: 300)
        try fixture.addSnippet(id: 4, list: 3, title: nil, blob: blob)
        try fixture.addSnippet(id: 5, list: 2, title: nil, blob: blob)

        let plan = try await readEverything(fixture.url).plan

        #expect(plan.history.map(\.snippetKey) == [3, 2, 1])
        #expect(plan.pinboards.map(\.snippetKey) == [5, 4])
    }

    @Test("a library one clip over the cap keeps every pinboard and the newest history, and says what it left")
    func whenOverTheCap_thenPinboardsAndNewestAreKept() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        let blob = try PasteFixture.archive("clip")
        try fixture.addMany(from: 1, count: 50, list: 2, blob: blob) { Double($0) }
        try fixture.addMany(from: 1001, count: PasteLibraryReaderTests.cap, list: 1, blob: blob) { Double($0) }

        let plan = try await readEverything(fixture.url, cap: ImportCap(maxClips: 5000, maxBytes: .max)).plan

        #expect(plan.pinboards.count == 50)
        #expect(plan.history.count == 4950)
        #expect(plan.history.first?.snippetKey == Int64(1000 + PasteLibraryReaderTests.cap))
        #expect(plan.historyLeftByCap == 1 && plan.libraryClips == 5001)
        #expect(plan.selectedCount + plan.leftByLimits + plan.unusable == plan.libraryClips)
    }

    static let cap = 4951

    @Test("the real cap: 20,001 clips take 20,000 and a library of any size is read without holding it")
    func whenOverTheRealCap_thenTwentyThousandAreTaken() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        let blob = try PasteFixture.archive("clip")
        try fixture.addMany(from: 1, count: 20_001, list: 1, blob: blob) { Double($0) }

        let plan = try await readEverything(fixture.url).plan

        #expect(plan.history.count == 20_000 && plan.historyLeftByCap == 1)
        #expect(plan.history.first?.snippetKey == 20_001 && plan.history.last?.snippetKey == 2)
    }

    @Test("a file over 1 GB is no longer refused: the cap counts the clips taken, not the file")
    func whenFileIsOverAGigabyte_thenStillRead() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: nil, blob: PasteFixture.archive("kept"))
        let handle = try FileHandle(forUpdating: fixture.url)
        try handle.truncate(atOffset: 1_100_000_000)
        try handle.close()

        let library = try await readEverything(fixture.url)

        #expect(library.records.count == 1)
    }

    private func scratchFolder() throws -> URL {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-reader-scratch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return scratch
    }

    @Test("the original file is left untouched and no temporary copy is left behind")
    func whenRead_thenOriginalUnchangedAndNoLeftovers() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: nil, blob: PasteFixture.archive("x"))
        let scratch = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let before = try Data(contentsOf: fixture.url)

        _ = try await readEverything(fixture.url, temporaryDirectory: scratch)

        #expect(try Data(contentsOf: fixture.url) == before)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty,
            "a work folder was left behind"
        )
    }

    @Test("the copy exists while the snapshot is open, and is gone once it is released without discard")
    func whenSnapshotIsReleased_thenCopyIsRemoved() throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: nil, blob: PasteFixture.archive("x"))
        let scratch = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: scratch) }

        var snapshot: PasteLibrarySnapshot? = try PasteLibrarySnapshot.open(
            databaseAt: fixture.url,
            temporaryDirectory: scratch
        )
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).count == 1)
        snapshot = nil

        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
        _ = snapshot
    }

    @Test("a copy a crashed Pesto left a day ago is removed, a recent one is not")
    func whenStaleCopiesExist_thenOnlyOldOnesGo() throws {
        let scratch = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let old = scratch.appendingPathComponent("pesto-paste-old")
        let recent = scratch.appendingPathComponent("pesto-paste-recent")
        let other = scratch.appendingPathComponent("someone-elses")
        for url in [old, recent, other] {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-90_000)],
            ofItemAtPath: old.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-90_000)],
            ofItemAtPath: other.path
        )

        PasteLibrarySnapshot.removeStaleFolders(in: scratch, fileManager: .default)

        let left = try Set(FileManager.default.contentsOfDirectory(atPath: scratch.path))
        #expect(left == ["pesto-paste-recent", "someone-elses"])
    }

    @Test("a missing file, a non-Paste database and a garbage file each fail with their own error")
    func whenNotALibrary_thenClearErrors() throws {
        #expect(throws: PasteLibraryReader.ReadError.notFound) {
            try PasteLibrarySnapshot.open(databaseAt: URL(fileURLWithPath: "/nonexistent/Paste.db"))
        }

        let other = FileManager.default.temporaryDirectory.appendingPathComponent("other-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: other) }
        var handle: OpaquePointer?
        sqlite3_open(other.path, &handle)
        sqlite3_exec(handle, "CREATE TABLE t (a INTEGER);", nil, nil, nil)
        sqlite3_close(handle)
        #expect(throws: PasteLibraryReader.ReadError.notAPasteLibrary) {
            try PasteLibrarySnapshot.open(databaseAt: other)
        }

        let garbage = FileManager.default.temporaryDirectory.appendingPathComponent("garbage-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: garbage) }
        try Data("not a database at all".utf8).write(to: garbage)
        #expect(throws: (any Error).self) { try PasteLibrarySnapshot.open(databaseAt: garbage) }
    }

    @Test("a database with damaged pages is an error, not a library that happens to be short")
    func whenPagesAreDamaged_thenReadingFails() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        let blob = try PasteFixture.archive(String(repeating: "pesto genovese ", count: 200))
        for id in 1...300 {
            try fixture.addSnippet(id: id, list: 2, title: "clip \(id)", blob: blob)
        }
        let size = try #require(
            try FileManager.default.attributesOfItem(atPath: fixture.url.path)[.size] as? Int
        )
        let handle = try FileHandle(forUpdating: fixture.url)
        try handle.seek(toOffset: UInt64(size / 2))
        try handle.write(contentsOf: Data(repeating: 0xFF, count: 16_384))
        try handle.close()

        await #expect(throws: (any Error).self) { try await readEverything(fixture.url) }
    }

    @Test("existingDatabaseURL finds Paste.db in the first candidate path that exists")
    func whenDatabaseInGroupContainer_thenFound() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-paste-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(PasteLibraryReader.existingDatabaseURL(homeDirectory: home) == nil)

        let groupDB = home.appendingPathComponent("Library/Group Containers/group.com.wiheads.paste/Paste.db")
        try FileManager.default.createDirectory(
            at: groupDB.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("sqlite".utf8).write(to: groupDB)

        #expect(PasteLibraryReader.existingDatabaseURL(homeDirectory: home) == groupDB)
    }
}
