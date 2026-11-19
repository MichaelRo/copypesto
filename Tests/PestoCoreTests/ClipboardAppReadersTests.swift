// SPDX-License-Identifier: MIT
import Foundation
import SQLite3
import Testing
@testable import PestoCore

private final class FixtureDatabase {
    let directory: URL?
    let url: URL
    private var db: OpaquePointer?

    init(_ statements: String, named name: String? = nil) throws {
        if let name {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("reader-fixture-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            directory = dir
            url = dir.appendingPathComponent(name)
        } else {
            directory = nil
            url = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString).sqlite")
        }
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw ClipboardAppLibraryReader.ReadError.unreadable }
        guard sqlite3_exec(db, statements, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw ClipboardAppLibraryReader.ReadError.unreadable
        }
        sqlite3_close(db)
    }

    func createExternalFile(subpath: String, data: Data) throws -> URL {
        let base = url.deletingLastPathComponent()
        let target = base.appendingPathComponent(subpath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: target)
        return target
    }

    deinit {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private func hex(_ text: String) -> String {
    Data(text.utf8).map { String(format: "%02x", $0) }.joined()
}

private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

@Suite("Shared external blob resolution")
struct ClipboardAppExternalBlobTests {
    @Test("when Core Data inline marker 0x01 is present, then prefix byte is stripped")
    func whenInlineMarkerPresent_thenStripsPrefix() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let inlineBlob = Data([0x01]) + png
        let fixture = try FixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP,
            ZLASTCOPIEDAT TIMESTAMP, ZPIN VARCHAR, ZTITLE VARCHAR);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, NULL, 'img');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.png', x'\(hex(inlineBlob))');
        """, named: "Storage.sqlite")

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(record.representations.map(\.uti) == ["public.png"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == png)
    }

    @Test("when Core Data 0x02 external file exists, then payload is resolved")
    func whenExternalFileExists_thenResolvesPayload() throws {
        let uuid = "5A438128-3203-4167-B824-9AE50648B842"
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let reference = "02" + hex(uuid) + "00"
        let fixture = try FixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP,
            ZLASTCOPIEDAT TIMESTAMP, ZPIN VARCHAR, ZTITLE VARCHAR);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, NULL, 'img');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.png', x'\(reference)');
        """, named: "Storage.sqlite")
        _ = try fixture.createExternalFile(subpath: ".Storage_SUPPORT/_EXTERNAL_DATA/\(uuid)", data: png)

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(record.representations.map(\.uti) == ["public.png"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == png)
    }

    @Test("when Core Data external file is a symlink, then payload is rejected")
    func whenExternalFileIsSymlink_thenRejectsPayload() throws {
        let uuid = "5A438128-3203-4167-B824-9AE50648B842"
        let reference = "02" + hex(uuid) + "00"
        let fixture = try FixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP,
            ZLASTCOPIEDAT TIMESTAMP, ZPIN VARCHAR, ZTITLE VARCHAR);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, NULL, 'img');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.png', x'\(reference)');
        """, named: "Storage.sqlite")
        let secret = try fixture.createExternalFile(subpath: "secret.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let extDir = fixture.url.deletingLastPathComponent()
            .appendingPathComponent(".Storage_SUPPORT/_EXTERNAL_DATA", isDirectory: true)
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: extDir.appendingPathComponent(uuid), withDestinationURL: secret
        )

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.isEmpty)
        #expect(library.skipped == 1)
    }

    @Test("when Core Data 0x02 reference contains path traversal, then payload is rejected")
    func whenExternalReferenceHasTraversal_thenRejectsPayload() throws {
        let traversal = "02" + hex("../../secret.png") + "00"
        let fixture = try FixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP,
            ZLASTCOPIEDAT TIMESTAMP, ZPIN VARCHAR, ZTITLE VARCHAR);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, NULL, 'img');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.png', x'\(traversal)');
        """, named: "Storage.sqlite")
        _ = try fixture.createExternalFile(subpath: "secret.png", data: Data([0x89, 0x50, 0x4E, 0x47]))

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.isEmpty)
        #expect(library.skipped == 1)
    }

    @Test("when external payload exceeds size limit, then read rejects without leaking")
    func whenExternalPayloadExceedsLimit_thenRejectsSafely() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let uuid = "5A438128-3203-4167-B824-9AE50648B842"
        try Data(repeating: 0xAA, count: 128).write(to: dir.appendingPathComponent(uuid))

        #expect(PasteExternalPayload.read(uuid, in: dir, limit: 64) == nil)
        #expect(PasteExternalPayload.read(uuid, in: dir, limit: 128)?.count == 128)
    }
}

@Suite("Maccy library reader")
struct MaccyLibraryReaderTests {
    private func maccy(_ rows: String, named name: String? = nil) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP,
            ZLASTCOPIEDAT TIMESTAMP, ZNUMBEROFCOPIES INTEGER, ZPIN VARCHAR, ZTITLE VARCHAR);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
        \(rows)
        """, named: name)
    }

    @Test("a text item becomes a record with its app and time, in its own representations")
    func readsText() throws {
        let fixture = try maccy("""
        INSERT INTO ZHISTORYITEM VALUES (1, 'com.apple.Notes', 700000000, 700000100, 1, NULL, 'hello');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.utf8-plain-text', x'\(hex("hello world"))');
        """)

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.sourceBundleID == "com.apple.Notes")
        #expect(record.pinboard == nil)
        #expect(record.timestamp == Date(timeIntervalSinceReferenceDate: 700_000_100))
        #expect(record.representations.map(\.uti) == ["public.utf8-plain-text"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("hello world".utf8))
    }

    @Test("several representations of one item stay together, in order")
    func groupsRepresentations() throws {
        let fixture = try maccy("""
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, 1, NULL, 't');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.rtf', x'\(hex("{\\rtf1 hi}"))');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (2, 1, 'public.utf8-plain-text', x'\(hex("hi"))');
        """)

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 1)
        #expect(library.records[0].representations.map(\.uti) == ["public.rtf", "public.utf8-plain-text"])
    }

    @Test("a value that is only a Core Data external-file reference is left out and counted, never imported as data")
    func externalReferenceIsNotImportedAsData() throws {
        let reference = "02" + hex("5A438128-3203-4167-B824-9AE50648B842") + "00"
        let fixture = try maccy("""
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, 1, NULL, 't');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.png', x'\(reference)');
        INSERT INTO ZHISTORYITEM VALUES (2, NULL, 1, 3, 1, NULL, 't');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (2, 2, 'public.png', x'\(reference)');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (3, 2, 'public.utf8-plain-text', x'\(hex("kept"))');
        """)

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 1 && library.skipped == 1)
        #expect(library.records[0].representations.map(\.uti) == ["public.utf8-plain-text"])
    }

    @Test("when Maccy 1.x CoreData.sqlite candidates are checked, both container and non-container paths appear")
    func whenMaccyCandidatesChecked_thenIncludesCoreDataFallback() {
        let home = URL(fileURLWithPath: "/tmp/maccy-home-\(UUID().uuidString)", isDirectory: true)
        let candidates = MaccyLibraryReader.candidateDatabaseURLs(homeDirectory: home)

        #expect(candidates.contains { $0.path.hasSuffix("Application Support/Maccy/Storage.sqlite") })
        #expect(candidates.contains {
            $0.path.hasSuffix("Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/CoreData.sqlite")
        })
        #expect(candidates.contains { $0.path.hasSuffix("Library/Application Support/Maccy/CoreData.sqlite") })
    }

    @Test("when Maccy 1.x CoreData.sqlite has external image blob, then resolves from .CoreData_SUPPORT")
    func whenMaccyCoreDataHasExternalImage_thenResolvesFromCoreDataSupport() throws {
        let uuid = "6B549239-4314-4278-C935-0BF61759C953"
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let reference = "02" + hex(uuid) + "00"
        let fixture = try maccy("""
        INSERT INTO ZHISTORYITEM VALUES (1, 'com.apple.Preview', 10, 20, 1, NULL, 'img');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.png', x'\(reference)');
        """, named: "CoreData.sqlite")
        _ = try fixture.createExternalFile(subpath: ".CoreData_SUPPORT/_EXTERNAL_DATA/\(uuid)", data: png)

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(record.representations.map(\.uti) == ["public.png"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == png)
    }

    @Test("when older Maccy schema lacks ZTITLE and ZFIRSTCOPIEDAT, then reads cleanly")
    func whenOlderMaccySchema_thenReadsCleanly() throws {
        let fixture = try FixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZLASTCOPIEDAT TIMESTAMP);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
        INSERT INTO ZHISTORYITEM VALUES (1, 'com.apple.TextEdit', 700000000);
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.utf8-plain-text', x'\(hex("legacy maccy"))');
        """)

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(record.pinboard == nil)
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("legacy maccy".utf8))
    }

    @Test("a pinned item lands in a collection of Maccy's pins")
    func pinnedItemsAreCollected() throws {
        let fixture = try maccy("""
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, 1, 'a', 't');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.utf8-plain-text', x'\(hex("keep"))');
        """)

        #expect(try MaccyLibraryReader.read(databaseAt: fixture.url).records.first?.pinboard == "Pinned in Maccy")
    }

    @Test("an item with no content is skipped, and counted")
    func skipsEmptyItems() throws {
        let fixture = try maccy("INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, 1, NULL, 't');")

        let library = try MaccyLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.isEmpty)
        #expect(library.skipped == 1)
    }

    @Test("a database that is not Maccy's, and a missing file, are told apart")
    func rejectsOtherFiles() throws {
        let other = try FixtureDatabase("CREATE TABLE something (x INTEGER);")

        #expect(throws: ClipboardAppLibraryReader.ReadError.notRecognized) {
            try MaccyLibraryReader.read(databaseAt: other.url)
        }
        #expect(throws: ClipboardAppLibraryReader.ReadError.notFound) {
            try MaccyLibraryReader.read(databaseAt: URL(fileURLWithPath: "/nonexistent/Storage.sqlite"))
        }
    }
}

@Suite("Alfred library reader")
struct AlfredLibraryReaderTests {
    private func alfred(_ rows: String, named name: String? = nil) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE clipboard (item TEXT, ts DECIMAL(10,2), app TEXT, apppath TEXT, dataType INTEGER, dataHash TEXT);
        \(rows)
        """, named: name)
    }

    @Test("a text clip becomes a record, with its app's name as the source and a Unix time")
    func readsText() throws {
        let fixture = try alfred("""
        INSERT INTO clipboard VALUES (
            'gas company 0501', 1760000000, 'Notes', '/System/Applications/Notes.app', 0, 'h'
        );
        """)

        let library = try AlfredLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(record.timestamp == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(record.representations.map(\.uti) == ["public.utf8-plain-text"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("gas company 0501".utf8))
    }

    @Test("a time counted from 2001, as Core Data does, is read as that")
    func readsReferenceDates() throws {
        let fixture = try alfred("INSERT INTO clipboard VALUES ('x', 700000000, NULL, NULL, 0, 'h');")

        #expect(try AlfredLibraryReader.read(databaseAt: fixture.url).records.first?.timestamp
            == Date(timeIntervalSinceReferenceDate: 700_000_000))
    }

    @Test("missing picture files are skipped and counted")
    func skipsPictures() throws {
        let fixture = try alfred("""
        INSERT INTO clipboard VALUES ('shot.png', 1760000000, NULL, NULL, 1, 'a.png');
        INSERT INTO clipboard VALUES ('a real clip', 1760000001, NULL, NULL, 0, 'b');
        """)

        let library = try AlfredLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 1)
        #expect(library.skipped == 1)
    }

    @Test("when Alfred image files exist in .data folder, then maps image UTIs")
    func whenAlfredImageExists_thenMapsImageUTIs() throws {
        let cases: [(ext: String, uti: String)] = [
            ("tiff", "public.tiff"), ("tif", "public.tiff"), ("png", "public.png"),
            ("jpg", "public.jpeg"), ("jpeg", "public.jpeg"), ("gif", "com.compuserve.gif"), ("heic", "public.heic")
        ]
        let inserts = cases.enumerated().map { index, item in
            "INSERT INTO clipboard VALUES ('Image', \(1_760_000_000 + index), NULL, NULL, 1, 'h\(index).\(item.ext)');"
        }.joined(separator: "\n")
        let fixture = try alfred(inserts, named: "clipboard.alfdb")
        for index in cases.indices {
            let ext = cases[index].ext
            _ = try fixture.createExternalFile(
                subpath: "clipboard.alfdb.data/h\(index).\(ext)", data: Data("img\(index)".utf8)
            )
        }

        let library = try AlfredLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == cases.count)
        for (index, expected) in cases.enumerated() {
            #expect(library.records[index].representations.map(\.uti) == [expected.uti])
            let decoded = Data(base64Encoded: library.records[index].representations[0].dataBase64)
            #expect(decoded == Data("img\(index)".utf8))
        }
    }

    @Test("when Alfred dataHash has path traversal or symlink, then rejects safely")
    func whenAlfredDataHashTraversalOrSymlink_thenRejectsSafely() throws {
        let fixture = try alfred("""
        INSERT INTO clipboard VALUES ('img1', 1760000000, NULL, NULL, 1, '../secret.png');
        INSERT INTO clipboard VALUES ('img2', 1760000001, NULL, NULL, 1, 'sub/bad.png');
        INSERT INTO clipboard VALUES ('img3', 1760000002, NULL, NULL, 1, 'link.png');
        """, named: "clipboard.alfdb")
        let secret = try fixture.createExternalFile(subpath: "secret.png", data: Data("nope".utf8))
        let dataDir = fixture.url.deletingLastPathComponent().appendingPathComponent("clipboard.alfdb.data")
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: dataDir.appendingPathComponent("link.png"), withDestinationURL: secret
        )

        let library = try AlfredLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.isEmpty)
        #expect(library.skipped == 3)
    }

    @Test("when Alfred dataType is 2 with plist, then imports multi-file URLs and falls back to item")
    func whenAlfredHasFileListPlist_thenImportsFileURLs() throws {
        let fixture = try alfred("""
        INSERT INTO clipboard VALUES ('a.pdf', 1760000000, NULL, NULL, 2, 'files.plist');
        INSERT INTO clipboard VALUES ('/Users/test/single.pdf', 1760000001, NULL, NULL, 2, 'missing.plist');
        """, named: "clipboard.alfdb")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["/Users/test/a.pdf", "/Users/test/b.png"], format: .binary, options: 0
        )
        _ = try fixture.createExternalFile(subpath: "clipboard.alfdb.data/files.plist", data: plistData)

        let library = try AlfredLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 2)
        #expect(library.records[0].representations.map(\.uti) == ["public.file-url"])
        let firstData = try #require(Data(base64Encoded: library.records[0].representations[0].dataBase64))
        #expect(String(data: firstData, encoding: .utf8) == "file:///Users/test/a.pdf\nfile:///Users/test/b.png")
        let secondData = try #require(Data(base64Encoded: library.records[1].representations[0].dataBase64))
        #expect(String(data: secondData, encoding: .utf8) == "file:///Users/test/single.pdf")
    }

    @Test("when older Alfred schema lacks dataHash column, then reads text cleanly")
    func whenOlderAlfredSchemaLacksDataHash_thenReadsText() throws {
        let fixture = try FixtureDatabase("""
        CREATE TABLE clipboard (item TEXT, ts DECIMAL(10,2), app TEXT, apppath TEXT, dataType INTEGER);
        INSERT INTO clipboard VALUES ('old alfred', 1760000000, 'Notes', NULL, 0);
        """)

        let library = try AlfredLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 1)
        #expect(Data(base64Encoded: library.records[0].representations[0].dataBase64) == Data("old alfred".utf8))
    }

    @Test("a file path is imported as a file clip")
    func readsFilePaths() throws {
        let fixture = try alfred(
            "INSERT INTO clipboard VALUES ('/Users/test/Documents/notes.pdf', 1760000000, NULL, NULL, 2, 'h');"
        )

        let record = try #require(try AlfredLibraryReader.read(databaseAt: fixture.url).records.first)

        #expect(record.representations.map(\.uti) == ["public.file-url"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) ==
            Data("file:///Users/test/Documents/notes.pdf".utf8))
    }

    @Test("a database that is not Alfred's is not recognised")
    func rejectsOtherFiles() throws {
        let other = try FixtureDatabase("CREATE TABLE something (x INTEGER);")

        #expect(throws: ClipboardAppLibraryReader.ReadError.notRecognized) {
            try AlfredLibraryReader.read(databaseAt: other.url)
        }
    }
}

@Suite("CopyClip library reader")
struct CopyClipLibraryReaderTests {
    @Test("modern ZCLIPPING table is read into plain text records")
    func readsModernTable() throws {
        let fixture = try FixtureDatabase("""
        CREATE TABLE ZCLIPPING (Z_PK INTEGER PRIMARY KEY, ZCONTENTS VARCHAR, ZDATERECORDED TIMESTAMP);
        INSERT INTO ZCLIPPING VALUES (1, 'copyclip clip', 700000000);
        """)
        let library = try CopyClipLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.representations.map(\.uti) == ["public.utf8-plain-text"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("copyclip clip".utf8))
    }

    @Test("legacy ZCLIPITEM table is also supported")
    func readsLegacyTable() throws {
        let fixture = try FixtureDatabase("""
        CREATE TABLE ZCLIPITEM (Z_PK INTEGER PRIMARY KEY, ZCONTENT VARCHAR, ZDATE TIMESTAMP);
        INSERT INTO ZCLIPITEM VALUES (1, 'legacy clip', 700000000);
        """)
        let library = try CopyClipLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.representations.map(\.uti) == ["public.utf8-plain-text"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("legacy clip".utf8))
    }

    @Test("unrecognized database is rejected")
    func rejectsUnrecognized() throws {
        let other = try FixtureDatabase("CREATE TABLE unknown (id INTEGER);")
        #expect(throws: ClipboardAppLibraryReader.ReadError.notRecognized) {
            try CopyClipLibraryReader.read(databaseAt: other.url)
        }
    }
}

@Suite("Flycut library reader")
struct FlycutLibraryReaderTests {
    @Test("reads Flycut property list with clippings and favorites")
    func readsFlycutPlist() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("flycut-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let dict: [String: Any] = [
            "store": [
                "jcList": [[
                    "Contents": "plain clip", "Timestamp": 1_760_000_000.0, "AppBundleURL": "/Applications/Notes.app"
                ]],
                "favoritesList": [[
                    "Contents": "fav clip", "Timestamp": 1_760_000_100.0, "AppBundleURL": "/Applications/Safari.app"
                ]]
            ]
        ]
        try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0).write(to: tempURL)

        let library = try FlycutLibraryReader.read(databaseAt: tempURL)
        #expect(library.records.count == 2)
        #expect(library.records[0].pinboard == "Favorites in Flycut")
        #expect(Data(base64Encoded: library.records[0].representations[0].dataBase64) == Data("fav clip".utf8))
        #expect(library.records[1].pinboard == nil)
        #expect(Data(base64Encoded: library.records[1].representations[0].dataBase64) == Data("plain clip".utf8))
    }
}

@Suite("Unclutter library reader")
struct UnclutterLibraryReaderTests {
    @Test("reads Unclutter history.plist and referenced content files")
    func readsUnclutterDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("unclutter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try "unclutter text".write(to: tempDir.appendingPathComponent("clip1.txt"), atomically: true, encoding: .utf8)
        let historyPlist: [String: Any] = [
            "0": [
                "content": "clip1.txt", "timestamp": Date(timeIntervalSince1970: 1_760_000_000),
                "sourceAppBundleId": "com.google.Chrome", "type": 0
            ]
        ]
        try PropertyListSerialization.data(fromPropertyList: historyPlist, format: .binary, options: 0)
            .write(to: tempDir.appendingPathComponent("history.plist"))

        let library = try UnclutterLibraryReader.read(databaseAt: tempDir)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.sourceBundleID == "com.google.Chrome")
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("unclutter text".utf8))
    }

    @Test("reads real staged libraries if present")
    func readsStagedLibraries() throws {
        let stagingDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/clipboard-staging")
        guard FileManager.default.fileExists(atPath: stagingDir.path) else { return }
        if FileManager.default.fileExists(atPath: stagingDir.appendingPathComponent("cleanclip.sqlite").path) {
            #expect(try !CleanClipLibraryReader.read(
                databaseAt: stagingDir.appendingPathComponent("cleanclip.sqlite")
            ).records.isEmpty)
        }
        if FileManager.default.fileExists(atPath: stagingDir.appendingPathComponent("pastenow.sqlite").path) {
            #expect(try !PasteNowLibraryReader.read(
                databaseAt: stagingDir.appendingPathComponent("pastenow.sqlite")
            ).records.isEmpty)
        }
        if FileManager.default.fileExists(atPath: stagingDir.appendingPathComponent("clipy.sqlite").path) {
            #expect(try !ClipyLibraryReader.read(
                databaseAt: stagingDir.appendingPathComponent("clipy.sqlite")
            ).records.isEmpty)
        }
        if FileManager.default.fileExists(atPath: stagingDir.appendingPathComponent("flycut.plist").path) {
            #expect(try !FlycutLibraryReader.read(
                databaseAt: stagingDir.appendingPathComponent("flycut.plist")
            ).records.isEmpty)
        }
        if FileManager.default.fileExists(atPath: stagingDir.appendingPathComponent("unclutter/Clipboard").path) {
            #expect(try !UnclutterLibraryReader.read(
                databaseAt: stagingDir.appendingPathComponent("unclutter/Clipboard")
            ).records.isEmpty)
        }
    }
}
