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
private struct PasteFixture {
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

    func close() {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite("Reading a Paste library")
struct PasteLibraryReaderTests {
    @Test("a library whose join table another version of Paste numbered differently is still read")
    func whenJoinTableHasOtherNumbers_thenStillRead() throws {
        let fixture = try PasteFixture(join: .init(name: "Z_7LISTS", snippets: "Z_7SNIPPETS", lists: "Z_14LISTS"))
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: "Deploy", blob: PasteFixture.archive("alembic upgrade head"))

        let library = try PasteLibraryReader.read(databaseAt: fixture.url)

        #expect(library.pinboards.first?.name == "Commands")
        #expect(library.pinboards.first?.records.count == 1)
    }

    @Test("a database with no join table between snippets and lists is not a Paste library")
    func whenNoJoinTable_thenNotAPasteLibrary() throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.run("DROP TABLE Z_6LISTS;")

        #expect(throws: PasteLibraryReader.ReadError.notAPasteLibrary) {
            try PasteLibraryReader.read(databaseAt: fixture.url)
        }
    }

    @Test("the sandbox container of the App Store version is among the places looked in")
    func whenAppStoreVersion_thenItsContainerIsCandidate() {
        let home = URL(fileURLWithPath: "/Users/someone")

        let paths = PasteLibraryReader.candidateDatabaseURLs(homeDirectory: home).map(\.path)

        #expect(paths.contains { $0.contains("Containers/com.wiheads.paste/") })
    }

    @Test("pinboards and history are read apart, in order, with titles, times and source apps")
    func whenLibraryHasBoardsAndHistory_thenSplit() throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: "Deploy", blob: PasteFixture.archive("alembic upgrade head"))
        try fixture.addSnippet(
            id: 2,
            list: 3,
            title: nil,
            blob: PasteFixture.archive("Review this", extraType: "public.html")
        )
        try fixture.addSnippet(id: 3, list: 1, title: nil, blob: PasteFixture.archive("from history"), seconds: 5000)

        let library = try PasteLibraryReader.read(databaseAt: fixture.url)

        #expect(library.pinboards.map(\.name) == ["Commands", "Prompts"])
        #expect(library.pinboardClipCount == 2)
        #expect(library.history.count == 1)
        let deploy = try #require(library.pinboards.first?.records.first)
        #expect(deploy.title == "Deploy")
        #expect(deploy.pinboard == "Commands")
        #expect(deploy.sourceBundleID == "com.example.editor")
        #expect(deploy.timestamp == Date(timeIntervalSinceReferenceDate: 1000))
        #expect(library.pinboardSummary == "Commands (1), Prompts (1)")
        #expect(library.history.first?.pinboard == nil)
        #expect(library.history.first?.timestamp == Date(timeIntervalSinceReferenceDate: 5000))
    }

    @Test("every representation is kept in Paste's order, so the importer can choose like a live copy does")
    func whenItemHasSeveralTypes_thenAllKeptInOrder() throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: nil, blob: PasteFixture.archive("hi", extraType: "public.html"))

        let record = try #require(PasteLibraryReader.read(databaseAt: fixture.url).pinboards.first?.records.first)

        #expect(record.representations.map(\.uti) == ["public.html", "public.utf8-plain-text"])
        #expect(Data(base64Encoded: record.representations[1].dataBase64) == Data("hi".utf8))
    }

    @Test("a snippet with no readable payload is skipped, not fatal")
    func whenPayloadIsGarbageOrMissing_thenSkipped() throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: nil, blob: Data([1, 2, 3, 4]))
        try fixture.addSnippet(id: 2, list: 2, title: nil, blob: nil)
        try fixture.addSnippet(id: 3, list: 2, title: nil, blob: PasteFixture.archive("kept"))

        let library = try PasteLibraryReader.read(databaseAt: fixture.url)

        #expect(library.pinboardClipCount == 1)
    }

    /// A file manager whose temporary directory is this test's own, so other tests that read a library at the same
    /// moment (each makes and removes a work folder) cannot show up in the listing.
    private final class PrivateTemporaryFileManager: FileManager, @unchecked Sendable {
        let folder: URL

        init(folder: URL) {
            self.folder = folder
            super.init()
        }

        override var temporaryDirectory: URL {
            folder
        }
    }

    @Test("the original file is left untouched and no temporary copy is left behind")
    func whenRead_thenOriginalUnchangedAndNoLeftovers() throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: nil, blob: PasteFixture.archive("x"))
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-reader-scratch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let before = try Data(contentsOf: fixture.url)

        _ = try PasteLibraryReader.read(
            databaseAt: fixture.url,
            fileManager: PrivateTemporaryFileManager(folder: scratch)
        )

        #expect(try Data(contentsOf: fixture.url) == before)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty,
            "a work folder was left behind"
        )
    }

    @Test("a missing file, a non-Paste database and a garbage file each fail with their own error")
    func whenNotALibrary_thenClearErrors() throws {
        #expect(throws: PasteLibraryReader.ReadError.notFound) {
            try PasteLibraryReader.read(databaseAt: URL(fileURLWithPath: "/nonexistent/Paste.db"))
        }

        let other = FileManager.default.temporaryDirectory.appendingPathComponent("other-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: other) }
        var handle: OpaquePointer?
        sqlite3_open(other.path, &handle)
        sqlite3_exec(handle, "CREATE TABLE t (a INTEGER);", nil, nil, nil)
        sqlite3_close(handle)
        #expect(throws: PasteLibraryReader.ReadError.notAPasteLibrary) { try PasteLibraryReader.read(databaseAt: other)
        }

        let garbage = FileManager.default.temporaryDirectory.appendingPathComponent("garbage-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: garbage) }
        try Data("not a database at all".utf8).write(to: garbage)
        #expect(throws: (any Error).self) { try PasteLibraryReader.read(databaseAt: garbage) }
    }

    @Test("a database with damaged pages is an error, not a library that happens to be short")
    func whenPagesAreDamaged_thenReadingFails() throws {
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

        #expect(throws: (any Error).self) { try PasteLibraryReader.read(databaseAt: fixture.url) }
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
