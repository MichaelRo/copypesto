// SPDX-License-Identifier: MIT
import CoreGraphics
import Foundation
import ImageIO
import SQLite3
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import PestoCore

private final class PastebotFixtureDatabase {
    let directory: URL
    let url: URL
    private var db: OpaquePointer?

    init(_ statements: String, named name: String = "Pastebot.sqlite") throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastebot-fixture-\(UUID().uuidString)", isDirectory: true)
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

@Suite("Pastebot library reader")
struct PastebotLibraryReaderTests {
    @Test("reads ZCLIP with ZPASTEBOARDDATA including Core Data 0x01 inline and 0x02 external image blobs")
    func whenPastebotHasPasteboardData_thenImportsTextAndExternalImages() throws {
        let uuid = "22334455-6677-4888-9999-AABBCCDDEEFF"
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let ref = "02" + hex(uuid) + "00"
        let inlineText = Data([0x01]) + Data("inline pastebot".utf8)
        let fixture = try PastebotFixtureDatabase("""
        CREATE TABLE ZCLIP (Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTIMESTAMP TIMESTAMP, ZBUNDLEIDENTIFIER VARCHAR);
        CREATE TABLE ZPASTEBOARDDATA (Z_PK INTEGER PRIMARY KEY, ZCLIP INTEGER, ZTYPE VARCHAR, ZDATA BLOB);
        INSERT INTO ZCLIP VALUES (1, 'My Clip', 700000000, 'com.apple.Notes');
        INSERT INTO ZCLIP VALUES (2, NULL, 700000100, 'com.apple.Preview');
        INSERT INTO ZPASTEBOARDDATA VALUES (1, 1, 'public.utf8-plain-text', x'\(hex(inlineText))');
        INSERT INTO ZPASTEBOARDDATA VALUES (2, 2, 'public.png', x'\(ref)');
        """)
        _ = try fixture.createExternalFile(subpath: ".Pastebot_SUPPORT/_EXTERNAL_DATA/\(uuid)", data: png)

        let library = try PastebotLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 2)
        #expect(library.records[0].title == "My Clip")
        #expect(library.records[0].sourceBundleID == "com.apple.Notes")
        #expect(Data(base64Encoded: library.records[0].representations[0].dataBase64) == Data("inline pastebot".utf8))
        #expect(library.records[1].representations.map(\.uti) == ["public.png"])
        #expect(Data(base64Encoded: library.records[1].representations[0].dataBase64) == png)
    }

    @Test("when ZPASTEBOARDDATA is absent, ZCLIP fallback imports ZDATA, ZPLAINTEXT, and ZSEARCHSTRING")
    func whenPastebotZClipOnly_thenImportsZDataZPlainTextAndZSearchString() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let fixture = try PastebotFixtureDatabase("""
        CREATE TABLE ZCLIP (
            Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTIMESTAMP TIMESTAMP, ZBUNDLEIDENTIFIER VARCHAR,
            ZDATA BLOB, ZPLAINTEXT VARCHAR, ZSEARCHSTRING VARCHAR
        );
        INSERT INTO ZCLIP VALUES (1, 'Pic', 700000000, 'com.apple.Preview', x'\(hex(png))', NULL, NULL);
        INSERT INTO ZCLIP VALUES (2, NULL, 700000100, 'com.apple.Notes', NULL, 'plain fallback', 'search fallback');
        INSERT INTO ZCLIP VALUES (3, 'Query', 700000200, 'com.apple.Safari', NULL, NULL, 'search only');
        INSERT INTO ZCLIP VALUES (4, NULL, 700000300, NULL, NULL, NULL, NULL);
        """)

        let library = try PastebotLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 3)
        #expect(library.skipped == 1)
        #expect(library.records[0].representations.map(\.uti) == ["public.png"])
        #expect(Data(base64Encoded: library.records[0].representations[0].dataBase64) == png)
        #expect(Data(base64Encoded: library.records[1].representations[0].dataBase64) == Data("plain fallback".utf8))
        #expect(library.records[2].title == "Query")
        #expect(Data(base64Encoded: library.records[2].representations[0].dataBase64) == Data("search only".utf8))
    }

    @Test("when Pastebot has ZPASTEBOARD or ZFOLDER tables, then populates custom collection name")
    func whenPastebotHasBoardsOrFolders_thenPopulatesPinboard() throws {
        let fixture = try PastebotFixtureDatabase("""
        CREATE TABLE ZPASTEBOARD (Z_PK INTEGER PRIMARY KEY, ZNAME VARCHAR);
        CREATE TABLE ZFOLDER (Z_PK INTEGER PRIMARY KEY, ZNAME VARCHAR);
        CREATE TABLE ZCLIP (
            Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTIMESTAMP TIMESTAMP, ZBUNDLEIDENTIFIER VARCHAR,
            ZPASTEBOARD INTEGER, ZFOLDER INTEGER
        );
        CREATE TABLE ZPASTEBOARDDATA (Z_PK INTEGER PRIMARY KEY, ZCLIP INTEGER, ZTYPE VARCHAR, ZDATA BLOB);
        INSERT INTO ZPASTEBOARD VALUES (1, 'Clipboard'), (2, 'Snippets');
        INSERT INTO ZFOLDER VALUES (10, 'Work');
        INSERT INTO ZCLIP VALUES (1, NULL, 10, NULL, 1, NULL);
        INSERT INTO ZCLIP VALUES (2, NULL, 20, NULL, 2, NULL);
        INSERT INTO ZCLIP VALUES (3, NULL, 30, NULL, NULL, 10);
        INSERT INTO ZPASTEBOARDDATA VALUES (1, 1, 'public.utf8-plain-text', x'\(hex("history item"))');
        INSERT INTO ZPASTEBOARDDATA VALUES (2, 2, 'public.utf8-plain-text', x'\(hex("snippet item"))');
        INSERT INTO ZPASTEBOARDDATA VALUES (3, 3, 'public.utf8-plain-text', x'\(hex("folder item"))');
        """)

        let library = try PastebotLibraryReader.read(databaseAt: fixture.url)

        #expect(library.records.count == 3)
        #expect(library.records[0].pinboard == nil)
        #expect(library.records[1].pinboard == "Snippets")
        #expect(library.records[2].pinboard == "Work")
    }

    @Test("when Pastebot candidate URLs checked, includes Group Containers for Pastebot2Mac and Pastebot3Mac")
    func whenCandidateURLsChecked_thenIncludesGroupContainers() {
        let home = URL(fileURLWithPath: "/tmp/pastebot-home-\(UUID().uuidString)", isDirectory: true)
        let candidates = PastebotLibraryReader.candidateDatabaseURLs(homeDirectory: home)

        #expect(candidates.contains { $0.path.contains("Group Containers/2775222H9T.com.tapbots.Pastebot2Mac") })
        #expect(candidates.contains { $0.path.contains("Group Containers/2775222H9T.com.tapbots.Pastebot3Mac") })
    }

    @Test("when Pastebot external file is symlink or unrecognized DB, rejects safely")
    func whenPastebotSymlinkOrUnrecognized_thenRejectsSafely() throws {
        let uuid = "33445566-7788-4999-AAAA-BBCCDDEEFF00"
        let ref = "02" + hex(uuid) + "00"
        let fixture = try PastebotFixtureDatabase("""
        CREATE TABLE ZCLIP (Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTIMESTAMP TIMESTAMP, ZBUNDLEIDENTIFIER VARCHAR);
        CREATE TABLE ZPASTEBOARDDATA (Z_PK INTEGER PRIMARY KEY, ZCLIP INTEGER, ZTYPE VARCHAR, ZDATA BLOB);
        INSERT INTO ZCLIP VALUES (1, NULL, 10, NULL);
        INSERT INTO ZPASTEBOARDDATA VALUES (1, 1, 'public.png', x'\(ref)');
        """)
        let secret = try fixture.createExternalFile(subpath: "secret.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        let extDir = fixture.directory.appendingPathComponent(".Pastebot_SUPPORT/_EXTERNAL_DATA")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: extDir.appendingPathComponent(uuid), withDestinationURL: secret
        )

        let library = try PastebotLibraryReader.read(databaseAt: fixture.url)
        #expect(library.records.isEmpty)
        #expect(library.skipped == 1)

        let other = try PastebotFixtureDatabase("CREATE TABLE logs (id INTEGER);")
        #expect(throws: ClipboardAppLibraryReader.ReadError.notRecognized) {
            try PastebotLibraryReader.read(databaseAt: other.url)
        }
        #expect(throws: ClipboardAppLibraryReader.ReadError.notFound) {
            try PastebotLibraryReader.read(databaseAt: URL(fileURLWithPath: "/nonexistent/Pastebot.sqlite"))
        }
    }
}

@Suite("End-to-end PasteMigrator ingestion of imported images")
struct ClipboardAppImageMigrationTests {
    private func makeImage(type: UTType, green: Double) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: green, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        try CGImageDestinationAddImage(destination, #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("imported images from Maccy, Alfred, CleanClip, PasteNow, PastePal, Pastebot, and Clipy ingest cleanly")
    func whenReadersImportImages_thenMigratorIngestsEncryptedImageItems() async throws {
        let png = try makeImage(type: .png, green: 0.15)
        let tiff = try makeImage(type: .tiff, green: 0.45)
        let jpeg = try makeImage(type: .jpeg, green: 0.75)

        let maccyUUID = "10000000-0000-4000-8000-000000000001"
        let maccy = try PastebotFixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP,
            ZLASTCOPIEDAT TIMESTAMP, ZPIN VARCHAR, ZTITLE VARCHAR);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE VARCHAR, ZVALUE BLOB);
        INSERT INTO ZHISTORYITEM VALUES (1, 'com.apple.Preview', 700000000, 700000100, 'pin', 'img');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.png', x'\("02" + hex(maccyUUID) + "00")');
        """, named: "Storage.sqlite")
        _ = try maccy.createExternalFile(subpath: ".Storage_SUPPORT/_EXTERNAL_DATA/\(maccyUUID)", data: png)

        let alfred = try PastebotFixtureDatabase("""
        CREATE TABLE clipboard (item TEXT, ts DECIMAL(10,2), app TEXT, apppath TEXT, dataType INTEGER, dataHash TEXT);
        INSERT INTO clipboard VALUES ('Image', 1760000000, NULL, NULL, 1, 'shot.tiff');
        """, named: "clipboard.alfdb")
        _ = try alfred.createExternalFile(subpath: "clipboard.alfdb.data/shot.tiff", data: tiff)

        let cleanclip = try PastebotFixtureDatabase("""
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION VARCHAR, ZFIRSTCOPIEDAT TIMESTAMP,
            ZLASTCOPIEDAT TIMESTAMP, ZALIAS VARCHAR, ZPIN VARCHAR, ZTITLE VARCHAR);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZPERSISTENTID VARCHAR,
            ZTYPE VARCHAR, ZMETADATA VARCHAR, ZPREVIEWDATA BLOB, ZVALUE BLOB);
        INSERT INTO ZHISTORYITEM VALUES (1, NULL, 1, 2, 'Design Mock', NULL, '\u{FFFC}');
        INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, NULL, 'public.png', NULL, x'\(hex(jpeg))', NULL);
        """)

        let records = try MaccyLibraryReader.read(databaseAt: maccy.url).records
            + AlfredLibraryReader.read(databaseAt: alfred.url).records
            + CleanClipLibraryReader.read(databaseAt: cleanclip.url).records

        let container = try ModelContainerSetup.makeInMemory()
        let summary = try await PasteMigrator(modelContainer: container).migrate(records: records)

        #expect(summary.imported == 3)
        let items = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.type == .image && $0.pixelWidth == 8 && $0.pixelHeight == 8 })
        #expect(items.contains { $0.collectionID != nil && !$0.isPinned && $0.customTitle == nil })
        #expect(items.contains { $0.customTitle == "Design Mock" })
    }

    @Test("imported images from PasteNow, PastePal, Pastebot, and Clipy ingest cleanly")
    func whenOtherReadersImportImages_thenMigratorIngestsEncryptedImageItems() async throws {
        let png = try makeImage(type: .png, green: 0.25)
        let tiffBot = try makeImage(type: .tiff, green: 0.55)
        let tiffClipy = try makeImage(type: .tiff, green: 0.65)
        let jpeg = try makeImage(type: .jpeg, green: 0.85)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [["type": "public.png", "data": png]], format: .binary, options: 0
        )
        let lzfse = try Data([0x01]) + ((plist as NSData).compressed(using: .lzfse) as Data)
        let pastenow = try PastebotFixtureDatabase("""
        CREATE TABLE ZPASTEITEM (Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTEXT VARCHAR, ZTIMESTAMP TIMESTAMP,
            ZAPPBUNDLEID VARCHAR, ZBASEUNIFORMTYPE VARCHAR, ZITEMDATA INTEGER);
        CREATE TABLE ZPASTEITEMDATA (Z_PK INTEGER PRIMARY KEY, ZCOMPRESSED INTEGER, ZPASTEITEM INTEGER, ZDATA BLOB);
        INSERT INTO ZPASTEITEM VALUES (1, 'PN Shot', NULL, 10, NULL, 'public.image', 1);
        INSERT INTO ZPASTEITEMDATA VALUES (1, 1, 1, x'\(hex(lzfse))');
        """)
        let pastepal = try PastebotFixtureDatabase("""
        CREATE TABLE ZCDCLIPBOARDITEM (Z_PK INTEGER PRIMARY KEY, ZCREATEDAT TIMESTAMP,
            ZNAME VARCHAR, ZCONTENTIMAGEFILEURL VARCHAR);
        INSERT INTO ZCDCLIPBOARDITEM VALUES (1, 20, 'Pal Shot', 'shot.jpg');
        """, named: "PastePal2.sqlite")
        _ = try pastepal.createExternalFile(subpath: "shot.jpg", data: jpeg)
        let pastebot = try PastebotFixtureDatabase("""
        CREATE TABLE ZCLIP (Z_PK INTEGER PRIMARY KEY, ZTITLE VARCHAR, ZTIMESTAMP TIMESTAMP,
            ZBUNDLEIDENTIFIER VARCHAR, ZDATA BLOB);
        INSERT INTO ZCLIP VALUES (1, 'Bot Shot', 30, NULL, x'\(hex(tiffBot))');
        """)
        let clipy = try PastebotFixtureDatabase("""
        CREATE TABLE pasteboardHistories (id TEXT PRIMARY KEY NOT NULL, title TEXT,
            pasteboardTypes TEXT, deviceID TEXT, updateAt INTEGER);
        CREATE TABLE pasteboardHistoryAssets (id TEXT PRIMARY KEY NOT NULL, pasteboardHistoryID TEXT NOT NULL,
            "index" INTEGER, pasteboardType TEXT, data BLOB);
        CREATE TABLE pasteboardHistoryThumbnailAssets (pasteboardHistoryID TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL, data BLOB NOT NULL);
        INSERT INTO pasteboardHistories VALUES ('h1', '', '["public.tiff"]', NULL, 40);
        INSERT INTO pasteboardHistoryThumbnailAssets VALUES ('h1', 'image', x'\(hex(tiffClipy))');
        """)
        let records = try PasteNowLibraryReader.read(databaseAt: pastenow.url).records
            + PastePalLibraryReader.read(databaseAt: pastepal.url).records
            + PastebotLibraryReader.read(databaseAt: pastebot.url).records
            + ClipyLibraryReader.read(databaseAt: clipy.url).records

        let container = try ModelContainerSetup.makeInMemory()
        let summary = try await PasteMigrator(modelContainer: container).migrate(records: records)

        #expect(summary.imported == 4)
        let items = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(items.count == 4)
        #expect(items.allSatisfy { $0.type == .image && $0.pixelWidth == 8 && $0.pixelHeight == 8 })
        #expect(items.contains { $0.customTitle == "PN Shot" })
        #expect(items.contains { $0.customTitle == "Pal Shot" })
        #expect(items.contains { $0.customTitle == "Bot Shot" })
    }
}
