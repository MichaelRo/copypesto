// SPDX-License-Identifier: MIT
import Foundation
import SQLite3
import Testing
@testable import PestoCore

/// A SQLite file built here with the table layout the reader expects, so no one's clips are needed. The layouts are
/// from the apps' published data models and should be checked against a real library.
private final class FixtureDatabase {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString).sqlite")
    private var db: OpaquePointer?

    init(_ statements: String) throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw ClipboardAppLibraryReader.ReadError.unreadable }
        guard sqlite3_exec(db, statements, nil, nil, nil) == SQLITE_OK else {
            throw ClipboardAppLibraryReader.ReadError.unreadable
        }
        sqlite3_close(db)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

private func hex(_ text: String) -> String {
    Data(text.utf8).map { String(format: "%02x", $0) }.joined()
}

@Suite("Maccy library reader")
struct MaccyLibraryReaderTests {
    private func maccy(_ rows: String) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP,
            ZLASTCOPIEDAT TIMESTAMP, ZNUMBEROFCOPIES INTEGER, ZPIN VARCHAR, ZTITLE VARCHAR);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
        \(rows)
        """)
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
    private func alfred(_ rows: String) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE clipboard (item TEXT, ts DECIMAL(10,2), app TEXT, apppath TEXT, dataType INTEGER, dataHash TEXT);
        \(rows)
        """)
    }

    @Test("a text clip becomes a record, with its app's name as the source and a Unix time")
    func readsText() throws {
        let fixture =
            try alfred(
                """
                INSERT INTO clipboard VALUES ('gas company 0501', 1760000000, 'Notes', \
                '/System/Applications/Notes.app', 0, 'h');
                """
            )

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

    @Test("pictures and anything that is not text are skipped and counted")
    func skipsPictures() throws {
        let fixture = try alfred("""
        INSERT INTO clipboard VALUES ('shot.png', 1760000000, NULL, NULL, 1, 'a');
        INSERT INTO clipboard VALUES ('a real clip', 1760000001, NULL, NULL, 0, 'b');
        """)

        let library = try AlfredLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 1)
        #expect(library.skipped == 1)
    }

    @Test("a file path is imported as a file clip")
    func readsFilePaths() throws {
        let fixture =
            try alfred(
                "INSERT INTO clipboard VALUES ('/Users/me/Documents/notes.pdf', 1760000000, NULL, NULL, 2, 'h');"
            )

        let record = try #require(try AlfredLibraryReader.read(databaseAt: fixture.url).records.first)

        #expect(record.representations.map(\.uti) == ["public.file-url"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) ==
            Data("file:///Users/me/Documents/notes.pdf".utf8))
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
    private func copyclip(_ rows: String) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE ZCLIPPING (Z_PK INTEGER PRIMARY KEY, ZCONTENTS VARCHAR, ZDATERECORDED TIMESTAMP);
        \(rows)
        """)
    }

    private func legacyCopyClip(_ rows: String) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE ZCLIPITEM (Z_PK INTEGER PRIMARY KEY, ZCONTENT VARCHAR, ZDATE TIMESTAMP);
        \(rows)
        """)
    }

    @Test("modern ZCLIPPING table is read into plain text records")
    func readsModernTable() throws {
        let fixture = try copyclip("""
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
        let fixture = try legacyCopyClip("""
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

@Suite("PastePal library reader")
struct PastePalLibraryReaderTests {
    private func modernPastePal(_ rows: String) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE ZCDCLIPBOARDITEM (
            Z_PK INTEGER PRIMARY KEY, ZSTRING VARCHAR, ZCREATEDAT TIMESTAMP, ZAPPBUNDLEID VARCHAR, ZISPINNED INTEGER
        );
        \(rows)
        """)
    }

    private func legacyPastePal(_ rows: String) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE ZPASTEDITEM (
            Z_PK INTEGER PRIMARY KEY, ZTEXT VARCHAR, ZDATE TIMESTAMP, \
            ZSOURCEAPPBUNDLEIDENTIFIER VARCHAR, ZISPINNED INTEGER
        );
        \(rows)
        """)
    }

    @Test("modern ZCDCLIPBOARDITEM table is read with bundle ID and pin")
    func readsModernTable() throws {
        let fixture = try modernPastePal("""
        INSERT INTO ZCDCLIPBOARDITEM VALUES (1, 'pal clip', 700000000, 'com.apple.Safari', 1);
        """)
        let library = try PastePalLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.sourceBundleID == "com.apple.Safari")
        #expect(record.pinboard == "Pinned in PastePal")
        #expect(record.representations.map(\.uti) == ["public.utf8-plain-text"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("pal clip".utf8))
    }

    @Test("legacy ZPASTEDITEM table is also supported")
    func readsLegacyTable() throws {
        let fixture = try legacyPastePal("""
        INSERT INTO ZPASTEDITEM VALUES (1, 'old pal clip', 700000000, 'com.apple.Notes', 0);
        """)
        let library = try PastePalLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.pinboard == nil)
        #expect(record.sourceBundleID == "com.apple.Notes")
    }
}

@Suite("CleanClip library reader")
struct CleanClipLibraryReaderTests {
    private func cleanclip(_ rows: String) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (
            Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP, ZLASTCOPIEDAT TIMESTAMP,
            ZPIN VARCHAR, ZTITLE VARCHAR
        );
        CREATE TABLE ZHISTORYITEMCONTENT (
            Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZMETADATA VARCHAR, ZVALUE BLOB
        );
        \(rows)
        """)
    }

    @Test("reads CleanClip clips from ZMETADATA or ZVALUE with pins")
    func readsCleanClipClips() throws {
        let fixture = try cleanclip("""
        INSERT INTO ZHISTORYITEM VALUES (1, 'com.antiless.cleanclip.mac', 700000000, 700000100, '1', 'Title');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.utf8-plain-text', 'CleanClip text', NULL);
        """)
        let library = try CleanClipLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.pinboard == "Pinned in CleanClip")
        #expect(record.title == "Title")
        #expect(record.sourceBundleID == "com.antiless.cleanclip.mac")
        #expect(record.representations.map(\.uti) == ["public.utf8-plain-text"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("CleanClip text".utf8))
    }
}

@Suite("PasteNow library reader")
struct PasteNowLibraryReaderTests {
    private func pastenow(_ rows: String) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE ZPASTEITEM (
            Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTEXT VARCHAR, ZTIMESTAMP TIMESTAMP,
            ZAPPBUNDLEID VARCHAR, ZBASEUNIFORMTYPE VARCHAR, ZRTFDATA BLOB, ZURLDATA BLOB, ZLIST INTEGER
        );
        CREATE TABLE ZPASTELIST (Z_PK INTEGER PRIMARY KEY, ZNAME VARCHAR);
        \(rows)
        """)
    }

    @Test("reads PasteNow clips with lists mapped to pinboards")
    func readsPasteNowItems() throws {
        let fixture = try pastenow("""
        INSERT INTO ZPASTELIST VALUES (2, 'Work');
        INSERT INTO ZPASTEITEM VALUES ( \
            1, 'Title', 'PasteNow text', 700000000, 'com.google.Chrome', 'public.text', NULL, NULL, 2 \
        );
        """)
        let library = try PasteNowLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.pinboard == "Work")
        #expect(record.sourceBundleID == "com.google.Chrome")
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("PasteNow text".utf8))
    }
}

@Suite("Clipy library reader")
struct ClipyLibraryReaderTests {
    private func clipy(_ rows: String) throws -> FixtureDatabase {
        try FixtureDatabase("""
        CREATE TABLE pasteboardHistories (
            id TEXT PRIMARY KEY NOT NULL, title TEXT, pasteboardTypes TEXT, deviceID TEXT, updateAt INTEGER
        );
        CREATE TABLE pasteboardHistoryAssets (
            id TEXT PRIMARY KEY NOT NULL, pasteboardHistoryID TEXT NOT NULL, \
            "index" INTEGER, pasteboardType TEXT, data BLOB
        );
        \(rows)
        """)
    }

    @Test("reads Clipy history and assets")
    func readsClipyHistory() throws {
        let fixture = try clipy("""
        INSERT INTO pasteboardHistories VALUES ('h1', 'Clipy clip', '[]', NULL, 1760000000);
        INSERT INTO pasteboardHistoryAssets VALUES ('a1', 'h1', 0, 'public.utf8-plain-text', x'\(hex("clipy text"))');
        """)
        let library = try ClipyLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.title == "Clipy clip")
        #expect(record.timestamp == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("clipy text".utf8))
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
                "jcList": [
                    [
                        "Contents": "plain clip",
                        "Timestamp": 1_760_000_000.0,
                        "AppBundleURL": "/Applications/Notes.app"
                    ]
                ],
                "favoritesList": [
                    [
                        "Contents": "fav clip",
                        "Timestamp": 1_760_000_100.0,
                        "AppBundleURL": "/Applications/Safari.app"
                    ]
                ]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        try data.write(to: tempURL)

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

        let clipFile = tempDir.appendingPathComponent("clip1.txt")
        try "unclutter text".write(to: clipFile, atomically: true, encoding: .utf8)

        let historyPlist: [String: Any] = [
            "0": [
                "content": "clip1.txt",
                "timestamp": Date(timeIntervalSince1970: 1_760_000_000),
                "sourceAppBundleId": "com.google.Chrome",
                "type": 0
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: historyPlist, format: .binary, options: 0)
        try data.write(to: tempDir.appendingPathComponent("history.plist"))

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

        let cleanclipURL = stagingDir.appendingPathComponent("cleanclip.sqlite")
        if FileManager.default.fileExists(atPath: cleanclipURL.path) {
            let lib = try CleanClipLibraryReader.read(databaseAt: cleanclipURL)
            #expect(!lib.records.isEmpty)
        }

        let pastenowURL = stagingDir.appendingPathComponent("pastenow.sqlite")
        if FileManager.default.fileExists(atPath: pastenowURL.path) {
            let lib = try PasteNowLibraryReader.read(databaseAt: pastenowURL)
            #expect(!lib.records.isEmpty)
        }

        let clipyURL = stagingDir.appendingPathComponent("clipy.sqlite")
        if FileManager.default.fileExists(atPath: clipyURL.path) {
            let lib = try ClipyLibraryReader.read(databaseAt: clipyURL)
            #expect(!lib.records.isEmpty)
        }

        let flycutURL = stagingDir.appendingPathComponent("flycut.plist")
        if FileManager.default.fileExists(atPath: flycutURL.path) {
            let lib = try FlycutLibraryReader.read(databaseAt: flycutURL)
            #expect(!lib.records.isEmpty)
        }

        let unclutterURL = stagingDir.appendingPathComponent("unclutter/Clipboard")
        if FileManager.default.fileExists(atPath: unclutterURL.path) {
            let lib = try UnclutterLibraryReader.read(databaseAt: unclutterURL)
            #expect(!lib.records.isEmpty)
        }
    }
}
