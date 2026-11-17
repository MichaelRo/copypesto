// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("Cancelling an import preview before migrating cleans up the snapshot", .serialized)
    @MainActor
    struct ImportPreviewCancelTests {
        private let forever = RetentionPolicy(maxAge: .infinity, maxItemCount: 1_000_000, maxTotalBytes: .max)

        @Test("open -> plan -> discard without migrate removes temporary snapshot and writes no clips")
        func whenPreviewDiscardedBeforeMigrate_thenSnapshotCleanedAndStoreEmpty() async throws {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-cancel-preview-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let dbURL = scratch.appendingPathComponent("Paste.db")
            let fixture = try MinimalPasteDB.create(at: dbURL)
            _ = fixture

            let container = try ModelContainerSetup.makeInMemory()
            let snapshot = try PasteLibrarySnapshot.open(databaseAt: dbURL, temporaryDirectory: scratch)
            let plan = try await snapshot.plan(cap: .paste, retention: forever)
            let preview = ImportPreview(paste: plan, snapshot: snapshot)

            #expect(preview.pinnedCount == 1)
            #expect(preview.historyCount == 1)
            let beforeDiscard = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
                .filter { $0.hasPrefix("pesto-paste-") }
            #expect(beforeDiscard.count == 1)

            // Simulate user clicking Cancel on the preview sheet without calling migrate.
            if let snap = preview.snapshot {
                await snap.discard()
            }

            let afterDiscard = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
                .filter { $0.hasPrefix("pesto-paste-") }
            #expect(afterDiscard.isEmpty)
            #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).isEmpty)
        }
    }
}

import SQLite3

private enum MinimalPasteDB {
    static func create(at url: URL) throws -> URL {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let handle = db else {
            sqlite3_close(db)
            throw PasteLibraryReader.ReadError.unreadable
        }
        defer { sqlite3_close(handle) }
        let sql = """
        CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR);
        INSERT INTO Z_PRIMARYKEY VALUES (14, 'PasteboardHistory'), (15, 'Pinboard');
        CREATE TABLE ZSNIPPETLIST (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZDISPLAYORDER INTEGER, ZNAME VARCHAR);
        CREATE TABLE ZSNIPPET (Z_PK INTEGER PRIMARY KEY, ZDISPLAYORDERINPINBOARD INTEGER, ZSOURCEAPPLICATION INTEGER,
            ZCREATEDAT TIMESTAMP, ZTIMESTAMP TIMESTAMP, ZTITLE VARCHAR);
        CREATE TABLE ZSNIPPETDATA (Z_PK INTEGER PRIMARY KEY, ZSNIPPET INTEGER, ZPASTEBOARDITEMS BLOB);
        CREATE TABLE ZAPPLICATION (Z_PK INTEGER PRIMARY KEY, ZBUNDLEIDENTIFIER VARCHAR);
        CREATE TABLE Z_6LISTS (Z_6SNIPPETS INTEGER, Z_13LISTS INTEGER);
        INSERT INTO ZAPPLICATION VALUES (1, 'com.example.editor');
        INSERT INTO ZSNIPPETLIST VALUES (1, 14, 0, 'Clipboard History'), (2, 15, 1, 'Commands');
        INSERT INTO ZSNIPPET VALUES (1, 1, 1, 1000, NULL, NULL), (2, 2, 1, 2000, NULL, NULL);
        INSERT INTO Z_6LISTS VALUES (1, 2), (2, 1);
        INSERT INTO ZSNIPPETDATA VALUES (1, 1, X'01'), (2, 2, X'01');
        """
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw PasteLibraryReader.ReadError.unreadable
        }
        return url
    }
}
