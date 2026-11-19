// SPDX-License-Identifier: MIT
import Foundation
import SQLite3
import Testing
@testable import PestoCore

private final class ModernFixtureDatabase {
    let directory: URL
    let url: URL
    private var db: OpaquePointer?

    init(_ statements: String, named name: String = "fixture.sqlite") throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("modern-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(name)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw ClipboardAppLibraryReader.ReadError.unreadable }
        guard sqlite3_exec(db, statements, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw ClipboardAppLibraryReader.ReadError.unreadable
        }
        sqlite3_close(db)
    }

    func createExternalFile(subpath: String, data: Data) throws -> URL {
        let target = directory.appendingPathComponent(subpath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: target)
        return target
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

private func hex(_ text: String) -> String {
    Data(text.utf8).map { String(format: "%02x", $0) }.joined()
}

private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

@Suite("CleanClip library reader")
struct CleanClipLibraryReaderTests {
    private func cleanclip(_ rows: String) throws -> ModernFixtureDatabase {
        try ModernFixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (
            Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP, ZLASTCOPIEDAT TIMESTAMP,
            ZALIAS VARCHAR, ZPIN VARCHAR, ZTITLE VARCHAR
        );
        CREATE TABLE ZHISTORYITEMCONTENT (
            Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZPERSISTENTID VARCHAR, ZTYPE VARCHAR,
            ZMETADATA VARCHAR, ZPREVIEWDATA BLOB, ZVALUE BLOB
        );
        \(rows)
        """, named: "Storage.sqlite")
    }

    @Test("reads CleanClip clips with ZALIAS for title and ignores auto ZTITLE")
    func readsCleanClipClips() throws {
        let fixture = try cleanclip("""
        INSERT INTO ZHISTORYITEM VALUES (
            1, 'com.antiless.cleanclip.mac', 700000000, 700000100, 'My Alias', '1', 'Auto'
        );
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, NULL, 'public.utf8-plain-text', 'CleanClip text', NULL, NULL);
        INSERT INTO ZHISTORYITEM VALUES (2, 'com.apple.Notes', 700000000, 700000200, NULL, NULL, 'Truncated preview');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (2, 2, NULL, 'public.utf8-plain-text', 'Full copied text', NULL, NULL);
        """)
        let library = try CleanClipLibraryReader.read(databaseAt: fixture.url)
        #expect(library.records.count == 2)
        #expect(library.records[0].pinboard == "Pinned in CleanClip")
        #expect(library.records[0].title == "My Alias")
        #expect(library.records[0].sourceBundleID == "com.antiless.cleanclip.mac")
        #expect(Data(base64Encoded: library.records[0].representations[0].dataBase64) == Data("CleanClip text".utf8))
        #expect(library.records[1].title == nil)
        #expect(library.records[1].pinboard == nil)
    }

    @Test("when image data is missing and ZTITLE is U+FFFC, never imports replacement character as text")
    func whenImageMissingAndTitleIsObjectReplacement_thenSkipsItem() throws {
        let fixture = try cleanclip("""
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 700000000, 700000100, NULL, NULL, '\u{FFFC}');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'A36CE7EA-697E-4392-99FF-F590B3338AFB', 'public.png', \
            NULL, NULL, NULL);
        """)

        let library = try CleanClipLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.isEmpty)
        #expect(library.skipped == 1)
    }

    @Test("when PrivateData external file exists, resolves payload and falls back to ZPREVIEWDATA JPEG when absent")
    func whenPrivateDataExistsOrAbsent_thenResolvesAndFallsBackToPreview() throws {
        let uuid1 = "A36CE7EA-697E-4392-99FF-F590B3338AFB"
        let uuid2 = "B47DF8FB-7A8F-4403-AA00-A601C4449B0C"
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let fixture = try cleanclip("""
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, NULL, NULL, '\u{FFFC}');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, '\(uuid1)', 'public.png', NULL, x'\(hex(jpeg))', NULL);
        INSERT INTO ZHISTORYITEM VALUES (2, NULL, 1, 3, NULL, NULL, '\u{FFFC}');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (2, 2, '\(uuid2)', 'public.png', NULL, x'\(hex(jpeg))', NULL);
        """)
        _ = try fixture.createExternalFile(subpath: "PrivateData/HistoryItemContents/\(uuid1).public.png", data: png)

        let library = try CleanClipLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 2)
        #expect(library.records[0].representations.map(\.uti) == ["public.png"])
        #expect(Data(base64Encoded: library.records[0].representations[0].dataBase64) == png)
        #expect(library.records[1].representations.map(\.uti) == ["public.jpeg"])
        #expect(Data(base64Encoded: library.records[1].representations[0].dataBase64) == jpeg)
    }

    @Test("when CleanClip PrivateData has traversal or symlink, then rejects safely")
    func whenCleanClipPrivateDataTraversalOrSymlink_thenRejectsSafely() throws {
        let uuid = "C58EA90C-8B90-4514-BB11-B712D5550C1D"
        let fixture = try cleanclip("""
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, NULL, NULL, '\u{FFFC}');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, '../../secret', 'public.png', NULL, NULL, NULL);
        INSERT INTO ZHISTORYITEM VALUES (2, NULL, 1, 3, NULL, NULL, '\u{FFFC}');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (2, 2, '\(uuid)', 'public.png', NULL, NULL, NULL);
        """)
        let secret = try fixture.createExternalFile(subpath: "secret.public.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let contentsDir = fixture.directory.appendingPathComponent("PrivateData/HistoryItemContents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: contentsDir.appendingPathComponent("\(uuid).public.png"), withDestinationURL: secret
        )

        let library = try CleanClipLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.isEmpty)
        #expect(library.skipped == 2)
    }

    @Test("when CleanClip has ZGROUPITEM collections, then excludes smart lists, soft-deleted, All, and Tutorial")
    func whenCleanClipHasGroups_thenPopulatesUserCollections() throws {
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZGROUPITEM (
            Z_PK INTEGER PRIMARY KEY, ZISSMARTLIST INTEGER, ZSOFTDELETED INTEGER, ZPIN INTEGER, ZNAME VARCHAR
        );
        CREATE TABLE Z_1ITEMS (Z_1GROUPS INTEGER, Z_2ITEMS INTEGER, PRIMARY KEY (Z_1GROUPS, Z_2ITEMS));
        CREATE TABLE ZHISTORYITEM (
            Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP, ZLASTCOPIEDAT TIMESTAMP,
            ZALIAS VARCHAR, ZPIN VARCHAR, ZTITLE VARCHAR
        );
        CREATE TABLE ZHISTORYITEMCONTENT (
            Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZPERSISTENTID VARCHAR, ZTYPE VARCHAR,
            ZMETADATA VARCHAR, ZPREVIEWDATA BLOB, ZVALUE BLOB
        );
        INSERT INTO ZGROUPITEM VALUES (1, 0, 0, 1, 'All'), (2, 1, 0, 2, 'Image'), (3, 0, 0, 3, 'Tutorial');
        INSERT INTO ZGROUPITEM VALUES (4, 0, 1, 4, 'Deleted'), (5, 0, 0, 5, 'Work');
        INSERT INTO ZHISTORYITEM VALUES (10, NULL, 1, 2, NULL, NULL, 't1'), (11, NULL, 1, 3, NULL, '1', 't2');
        INSERT INTO ZHISTORYITEM VALUES (12, NULL, 1, 4, NULL, NULL, 't3');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 10, NULL, 'public.utf8-plain-text', 'in work', NULL, NULL);
        INSERT INTO ZHISTORYITEMCONTENT VALUES (2, 11, NULL, 'public.utf8-plain-text', 'pinned only', NULL, NULL);
        INSERT INTO ZHISTORYITEMCONTENT VALUES (3, 12, NULL, 'public.utf8-plain-text', 'tutorial', NULL, NULL);
        INSERT INTO Z_1ITEMS VALUES (5, 10), (2, 11), (4, 11), (3, 12);
        """)

        let library = try CleanClipLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 3)
        #expect(library.records[0].pinboard == "Work")
        #expect(library.records[1].pinboard == "Pinned in CleanClip")
        #expect(library.records[2].pinboard == nil)
    }

    @Test("when older CleanClip schema lacks ZALIAS, ZPERSISTENTID, and ZPREVIEWDATA, then reads cleanly")
    func whenOlderCleanClipSchema_thenReadsCleanly() throws {
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (
            Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP, ZLASTCOPIEDAT TIMESTAMP,
            ZPIN VARCHAR, ZTITLE VARCHAR
        );
        CREATE TABLE ZHISTORYITEMCONTENT (
            Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZMETADATA VARCHAR, ZVALUE BLOB
        );
        INSERT INTO ZHISTORYITEM VALUES (1, 'com.apple.Notes', 700000000, 700000100, '1', 'Auto');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.utf8-plain-text', 'legacy cleanclip', NULL);
        """)

        let library = try CleanClipLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(record.pinboard == "Pinned in CleanClip")
        #expect(record.title == nil)
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("legacy cleanclip".utf8))
    }
}

@Suite("PasteNow library reader")
struct PasteNowLibraryReaderTests {
    @Test("reads PasteNow clips with lists mapped to pinboards")
    func readsPasteNowItems() throws {
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZPASTEITEM (
            Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTEXT VARCHAR, ZTIMESTAMP TIMESTAMP,
            ZAPPBUNDLEID VARCHAR, ZBASEUNIFORMTYPE VARCHAR, ZRTFDATA BLOB, ZURLDATA BLOB, ZLIST INTEGER
        );
        CREATE TABLE ZPASTELIST (Z_PK INTEGER PRIMARY KEY, ZNAME VARCHAR);
        INSERT INTO ZPASTELIST VALUES (2, 'Work');
        INSERT INTO ZPASTEITEM VALUES (
            1, 'Title', 'PasteNow text', 700000000, 'com.google.Chrome', 'public.text', NULL, NULL, 2
        );
        """)
        let library = try PasteNowLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.pinboard == "Work")
        #expect(record.title == "Title")
        #expect(record.sourceBundleID == "com.google.Chrome")
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("PasteNow text".utf8))
    }

    @Test("when PasteNow has LZFSE compressed ZPASTEITEMDATA inline and external, then decompresses and parses plist")
    func whenPasteNowHasLZFSEItemData_thenDecompressesAndParses() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let plist1 = try PropertyListSerialization.data(
            fromPropertyList: [
                ["type": "public.html", "data": Data("<b>hi</b>".utf8)],
                ["type": "public.utf8-plain-text", "data": Data("hi".utf8)]
            ],
            format: .binary, options: 0
        )
        let compressed1 = try Data([0x01]) + ((plist1 as NSData).compressed(using: .lzfse) as Data)
        let plist2 = try PropertyListSerialization.data(
            fromPropertyList: [["type": "public.png", "data": png]], format: .binary, options: 0
        )
        let compressed2 = try (plist2 as NSData).compressed(using: .lzfse) as Data
        let uuid = "11223344-5566-4777-8888-99AABBCCDDEE"
        let ref = "02" + hex(uuid) + "00"

        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZPASTEITEM (
            Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTEXT VARCHAR, ZTIMESTAMP TIMESTAMP, ZAPPBUNDLEID VARCHAR,
            ZBASEUNIFORMTYPE VARCHAR, ZRTFDATA BLOB, ZURLDATA BLOB, ZTHUMBNAILIMAGE BLOB, ZITEMDATA INTEGER,
            ZLIST INTEGER
        );
        CREATE TABLE ZPASTEITEMDATA (
            Z_PK INTEGER PRIMARY KEY, ZCOMPRESSED INTEGER, ZPASTEITEM INTEGER, ZDATA BLOB
        );
        CREATE TABLE ZPASTELIST (Z_PK INTEGER PRIMARY KEY, ZLISTTYPE INTEGER, ZNAME VARCHAR);
        INSERT INTO ZPASTELIST VALUES (1, -1, 'All'), (2, 1, 'Image'), (3, 0, 'Snippets');
        INSERT INTO ZPASTEITEM VALUES (1, NULL, 'hi', 10, 'com.apple.Safari', 'public.text', NULL, NULL, NULL, 1, 3);
        INSERT INTO ZPASTEITEM VALUES (2, NULL, NULL, 20, 'com.apple.Preview', 'public.image', NULL, NULL, NULL, 2, 2);
        INSERT INTO ZPASTEITEMDATA VALUES (1, 1, 1, x'\(hex(compressed1))');
        INSERT INTO ZPASTEITEMDATA VALUES (2, 1, 2, x'\(ref)');
        """, named: "PasteNow.sqlite")
        _ = try fixture.createExternalFile(subpath: ".PasteNow_SUPPORT/_EXTERNAL_DATA/\(uuid)", data: compressed2)

        let library = try PasteNowLibraryReader.read(databaseAt: fixture.url)

        try #require(library.records.count == 2)
        #expect(library.records[0].pinboard == "Snippets")
        #expect(library.records[0].representations.map(\.uti) == ["public.html", "public.utf8-plain-text"])
        #expect(library.records[1].pinboard == nil)
        #expect(library.records[1].representations.map(\.uti) == ["public.png"])
        #expect(Data(base64Encoded: library.records[1].representations[0].dataBase64) == png)
    }

    @Test("when PasteNow external image is missing, falls back to ZTHUMBNAILIMAGE and emits file-url for file paths")
    func whenPasteNowExternalMissingOrFileURL_thenFallsBackAndEmitsFileURL() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let missingRef = "02" + hex("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE") + "00"
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZPASTEITEM (
            Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTEXT VARCHAR, ZTIMESTAMP TIMESTAMP, ZAPPBUNDLEID VARCHAR,
            ZBASEUNIFORMTYPE VARCHAR, ZRTFDATA BLOB, ZURLDATA BLOB, ZTHUMBNAILIMAGE BLOB, ZITEMDATA INTEGER,
            ZLIST INTEGER
        );
        CREATE TABLE ZPASTEITEMDATA (Z_PK INTEGER PRIMARY KEY, ZCOMPRESSED INTEGER, ZPASTEITEM INTEGER, ZDATA BLOB);
        INSERT INTO ZPASTEITEM VALUES (
            1, NULL, NULL, 10, NULL, 'public.image', NULL, NULL, x'\(hex(Data([0x01]) + png))', 1, NULL
        );
        INSERT INTO ZPASTEITEM VALUES (
            2, NULL, '/Users/test/notes.pdf', 20, NULL, 'public.file-url', NULL, NULL, NULL, NULL, NULL
        );
        INSERT INTO ZPASTEITEM VALUES (
            3, NULL, NULL, 30, NULL, 'public.text', NULL, NULL, NULL, 3, NULL
        );
        INSERT INTO ZPASTEITEMDATA VALUES (1, 1, 1, x'\(missingRef)');
        INSERT INTO ZPASTEITEMDATA VALUES (3, 1, 3, x'01deadbeef');
        """, named: "PasteNow.sqlite")

        let library = try PasteNowLibraryReader.read(databaseAt: fixture.url)

        try #require(library.records.count == 2)
        #expect(library.skipped == 1)
        #expect(library.records[0].representations.map(\.uti) == ["public.png"])
        #expect(Data(base64Encoded: library.records[0].representations[0].dataBase64) == png)
        #expect(library.records[1].representations.map(\.uti) == ["public.file-url"])
        let fileData = try #require(Data(base64Encoded: library.records[1].representations[0].dataBase64))
        #expect(String(data: fileData, encoding: .utf8) == "file:///Users/test/notes.pdf")
    }

    @Test("when older PasteNow schema lacks ZPASTEITEMDATA and ZTHUMBNAILIMAGE, reads legacy columns cleanly")
    func whenOlderPasteNowSchema_thenReadsLegacyColumns() throws {
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZPASTEITEM (
            Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTEXT VARCHAR, ZTIMESTAMP TIMESTAMP,
            ZAPPBUNDLEID VARCHAR, ZRTFDATA BLOB, ZURLDATA BLOB
        );
        INSERT INTO ZPASTEITEM VALUES (1, NULL, 'legacy pastenow', 700000000, 'com.apple.Notes', NULL, NULL);
        """)

        let library = try PasteNowLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.pinboard == nil)
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("legacy pastenow".utf8))
    }

    @Test("when LZFSE output exceeds limit, bounded decompression returns nil")
    func whenLZFSEExceedsLimit_thenReturnsNil() throws {
        let big = Data(repeating: 0x41, count: 4096)
        let compressed = try (big as NSData).compressed(using: .lzfse) as Data

        #expect(PasteNowLibraryReader.decompressLZFSE(compressed, limit: 1024) == nil)
        #expect(PasteNowLibraryReader.decompressLZFSE(compressed, limit: 4096) == big)
    }

    @Test("when PasteNow plist has file-reference URL and ZTEXT has path, prefers readable path URL")
    func whenPasteNowHasFileReferenceURL_thenPrefersPathFileURL() throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [["type": "public.file-url", "data": Data("file:///.file/id=1.2".utf8)]],
            format: .binary, options: 0
        )
        let compressed = try Data([0x01]) + ((plist as NSData).compressed(using: .lzfse) as Data)
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZPASTEITEM (Z_PK INTEGER PRIMARY KEY, ZTEXT VARCHAR, ZTIMESTAMP TIMESTAMP,
            ZBASEUNIFORMTYPE VARCHAR, ZITEMDATA INTEGER);
        CREATE TABLE ZPASTEITEMDATA (Z_PK INTEGER PRIMARY KEY, ZCOMPRESSED INTEGER, ZPASTEITEM INTEGER, ZDATA BLOB);
        INSERT INTO ZPASTEITEM VALUES (1, '/Users/test/photo.png', 10, 'public.file-url', 1);
        INSERT INTO ZPASTEITEMDATA VALUES (1, 1, 1, x'\(hex(compressed))');
        """)

        let library = try PasteNowLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(record.representations.map(\.uti) == ["public.file-url"])
        let data = try #require(Data(base64Encoded: record.representations[0].dataBase64))
        #expect(String(data: data, encoding: .utf8) == "file:///Users/test/photo.png")
    }
}

@Suite("PastePal library reader")
struct PastePalLibraryReaderTests {
    @Test("modern ZCDCLIPBOARDITEM table is read with bundle ID and pin")
    func readsModernTable() throws {
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZCDCLIPBOARDITEM (
            Z_PK INTEGER PRIMARY KEY, ZSTRING VARCHAR, ZCREATEDAT TIMESTAMP, ZAPPBUNDLEID VARCHAR, ZISPINNED INTEGER
        );
        INSERT INTO ZCDCLIPBOARDITEM VALUES (1, 'pal clip', 700000000, 'com.apple.Safari', 1);
        """)
        let library = try PastePalLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.sourceBundleID == "com.apple.Safari")
        #expect(record.pinboard == "Pinned in PastePal")
        #expect(record.representations.map(\.uti) == ["public.utf8-plain-text"])
    }

    @Test("legacy ZPASTEDITEM table is also supported")
    func readsLegacyTable() throws {
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZPASTEDITEM (
            Z_PK INTEGER PRIMARY KEY, ZTEXT VARCHAR, ZDATE TIMESTAMP,
            ZSOURCEAPPBUNDLEIDENTIFIER VARCHAR, ZISPINNED INTEGER
        );
        INSERT INTO ZPASTEDITEM VALUES (1, 'old pal clip', 700000000, 'com.apple.Notes', 0);
        """)
        let library = try PastePalLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.pinboard == nil)
        #expect(record.sourceBundleID == "com.apple.Notes")
    }

    @Test("when PastePal2 has blobs, images, RTF, file/link URLs, title, collections, and deleted items")
    func whenPastePal2FullSchema_thenImportsRichRecordsAndFiltersDeleted() throws {
        let uuid = "12345678-1234-4234-8234-1234567890AB"
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let colID = hex("col-work")
        let ref = "02" + hex(uuid) + "00"
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZCDBLOB (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZDATA BLOB);
        CREATE TABLE ZCDCOLLECTION (Z_PK INTEGER PRIMARY KEY, ZNAME VARCHAR, ZID BLOB);
        CREATE TABLE ZCDCLIPBOARDITEM (
            Z_PK INTEGER PRIMARY KEY, ZISPINNED INTEGER, ZMARKEDDELETE INTEGER, ZBLOB INTEGER,
            ZCREATEDAT TIMESTAMP, ZAPPBUNDLEID VARCHAR, ZITEMTYPE VARCHAR, ZNAME VARCHAR, ZPBTYPE VARCHAR,
            ZSTRING VARCHAR, ZCOLLECTIONID BLOB, ZCONTENTFILEURL VARCHAR, ZCONTENTIMAGEFILEURL VARCHAR,
            ZCONTENTLINKURL VARCHAR, ZCONTENTRICHTEXTDATA BLOB
        );
        INSERT INTO ZCDCOLLECTION VALUES (1, 'Work', x'\(colID)');
        INSERT INTO ZCDBLOB VALUES (1, 1, x'\(ref)');
        INSERT INTO ZCDCLIPBOARDITEM VALUES (
            1, 0, 0, 1, 10, 'com.apple.Preview', 'image', 'Logo', 'public.png', NULL, x'\(colID)',
            NULL, NULL, NULL, NULL
        );
        INSERT INTO ZCDCLIPBOARDITEM VALUES (
            2, 0, 0, NULL, 20, 'com.apple.Finder', 'image', 'Shot', NULL, NULL, NULL,
            NULL, 'images/shot.jpg', NULL, NULL
        );
        INSERT INTO ZCDCLIPBOARDITEM VALUES (
            3, 1, 0, NULL, 30, 'com.apple.TextEdit', 'text', 'Note', NULL, 'Hello', NULL,
            NULL, NULL, 'https://example.com', x'\(hex("{\\rtf1 Hello}"))'
        );
        INSERT INTO ZCDCLIPBOARDITEM VALUES (
            4, 0, 1, NULL, 40, NULL, 'text', NULL, NULL, 'Deleted clip', NULL, NULL, NULL, NULL, NULL
        );
        INSERT INTO ZCDCLIPBOARDITEM VALUES (
            5, 0, 0, NULL, 50, NULL, 'file', NULL, NULL, NULL, NULL, '/Users/test/doc.pdf', NULL, NULL, NULL
        );
        """, named: "PastePal2.sqlite")
        _ = try fixture.createExternalFile(subpath: ".PastePal2_SUPPORT/_EXTERNAL_DATA/\(uuid)", data: png)
        _ = try fixture.createExternalFile(subpath: "images/shot.jpg", data: jpeg)

        let library = try PastePalLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 4)
        #expect(library.records[0].title == "Logo")
        #expect(library.records[0].pinboard == "Work")
        #expect(library.records[0].representations.map(\.uti) == ["public.png"])
        #expect(library.records[1].title == "Shot")
        #expect(library.records[1].representations.map(\.uti) == ["public.jpeg"])
        #expect(library.records[2].pinboard == "Pinned in PastePal")
        #expect(Set(library.records[2].representations.map(\.uti))
            == Set(["public.url", "public.rtf", "public.utf8-plain-text"]))
        #expect(library.records[3].representations.map(\.uti) == ["public.file-url"])
    }

    @Test("when PastePal2 ZCONTENTIMAGEFILEURL has traversal, outside path, or symlink, then rejects safely")
    func whenPastePal2ImagePathUnsafe_thenRejectsSafely() throws {
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE ZCDCLIPBOARDITEM (
            Z_PK INTEGER PRIMARY KEY, ZCREATEDAT TIMESTAMP, ZCONTENTIMAGEFILEURL VARCHAR
        );
        INSERT INTO ZCDCLIPBOARDITEM VALUES (1, 10, '../secret.png');
        INSERT INTO ZCDCLIPBOARDITEM VALUES (2, 20, '/etc/passwd');
        INSERT INTO ZCDCLIPBOARDITEM VALUES (3, 30, 'images/link.png');
        """, named: "PastePal2.sqlite")
        let secret = try fixture.createExternalFile(subpath: "secret.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let imagesDir = fixture.directory.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: imagesDir.appendingPathComponent("link.png"), withDestinationURL: secret
        )

        let library = try PastePalLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.isEmpty)
        #expect(library.skipped == 3)
    }
}

@Suite("Clipy library reader")
struct ClipyLibraryReaderTests {
    private func clipy(_ rows: String) throws -> ModernFixtureDatabase {
        try ModernFixtureDatabase("""
        CREATE TABLE pasteboardHistories (
            id TEXT PRIMARY KEY NOT NULL, title TEXT, pasteboardTypes TEXT, deviceID TEXT, updateAt INTEGER
        );
        CREATE TABLE pasteboardHistoryAssets (
            id TEXT PRIMARY KEY NOT NULL, pasteboardHistoryID TEXT NOT NULL,
            "index" INTEGER, pasteboardType TEXT, data BLOB
        );
        \(rows)
        """, named: "sqlite.db")
    }

    @Test("reads Clipy history and assets without setting auto-truncated preview as custom title")
    func readsClipyHistory() throws {
        let fixture = try clipy("""
        INSERT INTO pasteboardHistories VALUES ('h1', 'Clipy clip', '[]', NULL, 1760000000);
        INSERT INTO pasteboardHistoryAssets VALUES ('a1', 'h1', 0, 'public.utf8-plain-text', x'\(hex("clipy text"))');
        """)
        let library = try ClipyLibraryReader.read(databaseAt: fixture.url)
        let record = try #require(library.records.first)
        #expect(library.records.count == 1)
        #expect(record.title == nil)
        #expect(record.timestamp == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("clipy text".utf8))
    }

    @Test("when Clipy history has no assets, falls back to title as plain text with nil custom title")
    func whenClipyHistoryHasNoAssets_thenTitleFallsBackToPlainText() throws {
        let fixture = try clipy("INSERT INTO pasteboardHistories VALUES ('h1', 'Fallback title', '[]', NULL, 100);")

        let library = try ClipyLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(record.title == nil)
        #expect(record.representations.map(\.uti) == ["public.utf8-plain-text"])
        #expect(Data(base64Encoded: record.representations[0].dataBase64) == Data("Fallback title".utf8))
    }

    @Test("when Clipy image history has no image asset, falls back to thumbnail asset as public.tiff")
    func whenClipyImageMissingAsset_thenFallsBackToThumbnailTiff() throws {
        let tiff = Data([0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00])
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE pasteboardHistories (
            id TEXT PRIMARY KEY NOT NULL, title TEXT, pasteboardTypes TEXT, deviceID TEXT, updateAt INTEGER
        );
        CREATE TABLE pasteboardHistoryAssets (
            id TEXT PRIMARY KEY NOT NULL, pasteboardHistoryID TEXT NOT NULL,
            "index" INTEGER, pasteboardType TEXT, data BLOB
        );
        CREATE TABLE pasteboardHistoryThumbnailAssets (
            pasteboardHistoryID TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, data BLOB NOT NULL
        );
        INSERT INTO pasteboardHistories VALUES ('h1', '', '["public.png","public.html"]', NULL, 100);
        INSERT INTO pasteboardHistoryAssets VALUES ('a1', 'h1', 0, 'public.html', x'\(hex("<img>"))');
        INSERT INTO pasteboardHistoryThumbnailAssets VALUES ('h1', 'image', x'\(hex(tiff))');
        """, named: "sqlite.db")

        let library = try ClipyLibraryReader.read(databaseAt: fixture.url)

        let record = try #require(library.records.first)
        #expect(record.representations.contains { $0.uti == "public.tiff" })
        let tiffRep = try #require(record.representations.first { $0.uti == "public.tiff" })
        #expect(Data(base64Encoded: tiffRep.dataBase64) == tiff)
    }

    @Test("when Clipy has snippets and snippetFolders, imports enabled snippets only")
    func whenClipyHasSnippets_thenImportsEnabledSnippets() throws {
        let fixture = try ModernFixtureDatabase("""
        CREATE TABLE pasteboardHistories (
            id TEXT PRIMARY KEY NOT NULL, title TEXT, pasteboardTypes TEXT, deviceID TEXT, updateAt INTEGER
        );
        CREATE TABLE pasteboardHistoryAssets (
            id TEXT PRIMARY KEY NOT NULL, pasteboardHistoryID TEXT NOT NULL,
            "index" INTEGER, pasteboardType TEXT, data BLOB
        );
        CREATE TABLE snippetFolders (
            id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, "index" INTEGER NOT NULL, isEnabled INTEGER NOT NULL
        );
        CREATE TABLE snippets (
            id TEXT PRIMARY KEY NOT NULL, folderID TEXT NOT NULL, title TEXT NOT NULL,
            content TEXT NOT NULL, "index" INTEGER NOT NULL, isEnabled INTEGER NOT NULL
        );
        INSERT INTO snippetFolders VALUES ('f1', 'Email', 0, 1), ('f2', 'Disabled', 1, 0), ('f3', '', 2, 1);
        INSERT INTO snippets VALUES ('s1', 'f1', 'Sig', 'Best regards', 0, 1);
        INSERT INTO snippets VALUES ('s2', 'f1', 'Off', 'hidden', 1, 0);
        INSERT INTO snippets VALUES ('s3', 'f2', 'InOffFolder', 'hidden2', 0, 1);
        INSERT INTO snippets VALUES ('s4', 'f3', 'NoFolderName', 'fallback board', 0, 1);
        """, named: "sqlite.db")

        let library = try ClipyLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 2)
        #expect(library.records[0].title == "Sig")
        #expect(library.records[0].pinboard == "Email")
        #expect(Data(base64Encoded: library.records[0].representations[0].dataBase64) == Data("Best regards".utf8))
        #expect(library.records[1].title == "NoFolderName")
        #expect(library.records[1].pinboard == "Snippets in Clipy")
    }
}
