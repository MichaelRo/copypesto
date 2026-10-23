// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("PasteMigrator")
struct PasteMigratorTests {
    private func textRecord(
        pinboard: String,
        title: String? = nil,
        text: String,
        uti: String = "public.utf8-plain-text"
    )
    -> PasteImportRecord {
        PasteImportRecord(
            pinboard: pinboard,
            title: title,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            sourceBundleID: "com.example.app",
            representations: [.init(uti: uti, dataBase64: Data(text.utf8).base64EncodedString())]
        )
    }

    private func items(in container: ModelContainer) throws -> [ClipboardItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
    }

    private func boards(in container: ModelContainer) throws -> [Pinboard] {
        try ModelContext(container).fetch(FetchDescriptor<Pinboard>())
    }

    @Test("imports a text record, pins it, and creates the target collection")
    func migrate_textRecord_pinsAndCreatesCollection() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        let summary = try await migrator.migrate(
            records: [textRecord(pinboard: "Commands", text: "alembic upgrade head")]
        )

        #expect(summary.imported == 1)
        let stored = try items(in: container)
        #expect(stored.count == 1)
        let item = try #require(stored.first)
        #expect(item.isPinned)
        #expect(item.displayPreviewText == "alembic upgrade head")

        let commands = try #require(boards(in: container).first { $0.name == "Commands" })
        #expect(item.collectionID == commands.id)
    }

    @Test("one Undo takes an import back with the collections it made, and Redo brings both back")
    func migrate_withHistory_isOneUndoableAction() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let history = UndoHistory()
        let service = StorageService(modelContainer: container, environment: .testing { $0.undoHistory = history })

        let summary = try await PasteMigrator(modelContainer: container).migrate(
            records: [
                textRecord(pinboard: "Commands", text: "alembic upgrade head"),
                textRecord(pinboard: "Commands", text: "git status")
            ],
            undoHistory: history
        )
        #expect(summary.imported == 2)
        #expect(history.undoLabel == .addClips(.imported, 2))

        try await service.undo()
        #expect(try items(in: container).isEmpty)
        #expect(try boards(in: container).isEmpty)

        try await service.redo()
        #expect(try items(in: container).count == 2)
        #expect(try boards(in: container).map(\.name) == ["Commands"])
    }

    private func record(_ representations: [(String, String)]) -> PasteImportRecord {
        PasteImportRecord(
            pinboard: "Useful Info",
            title: "gas",
            timestamp: .now,
            sourceBundleID: nil,
            representations: representations.map {
                .init(uti: $0.0, dataBase64: Data($0.1.utf8).base64EncodedString())
            }
        )
    }

    @Test("a rich-text record with a plain-text copy imports the plain text, as a live copy does")
    func migrate_richTextWithPlainText_importsThePlainText() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        _ = try await migrator.migrate(records: [record([
            ("public.rtf", #"{\rtf1\ansi Call the gas company}"#),
            ("public.utf8-plain-text", "Call the gas company")
        ])])

        let item = try #require(items(in: container).first)
        #expect(item.type == .text)
        #expect(item.displayPreviewText == "Call the gas company")
    }

    @Test("an imported text clip keeps the formatting it was copied with, as a live copy does")
    func migrate_richTextWithPlainText_keepsTheFormatting() throws {
        let rtf = #"{\rtf1\ansi {\b Dear} neighbour}"#
        let capture = try #require(PasteMigrator.makeCapture(from: record([
            ("public.rtf", rtf),
            ("public.html", "<b>Dear</b> neighbour"),
            ("public.utf8-plain-text", "Dear neighbour")
        ])))

        #expect(capture.payloadString == "Dear neighbour")
        #expect(capture.richPayload?.rtf == Data(rtf.utf8))
        #expect(capture.richPayload?.html == Data("<b>Dear</b> neighbour".utf8))
    }

    @Test("a plain-text record carries no rich payload")
    func migrate_plainText_hasNoRichPayload() throws {
        let capture = try #require(PasteMigrator.makeCapture(from: record([("public.utf8-plain-text", "plain")])))

        #expect(capture.richPayload == nil)
    }

    @Test("a rich flavour over the live capture's size limit is left out")
    func migrate_hugeRichFlavour_isDropped() throws {
        let huge = String(repeating: "x", count: PasteboardWatcher.maxRichTextBytes + 1)
        let capture = try #require(PasteMigrator.makeCapture(from: record([
            ("public.html", huge), ("public.utf8-plain-text", "short")
        ])))

        #expect(capture.richPayload == nil)
    }

    @Test("a record the old app marked concealed or transient is not imported", arguments: [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.apple.is-sensitive"
    ])
    func migrate_concealedRecord_isSkipped(marker: String) async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        let summary = try await migrator.migrate(records: [record([
            ("public.utf8-plain-text", "hunter2 is the password"), (marker, "")
        ])])

        #expect(summary.imported == 0)
        #expect(summary.skipped == 1)
        #expect(try items(in: container).isEmpty)
    }

    @Test("a rich-text record with no plain-text copy is flattened to its text")
    func migrate_richTextOnly_isFlattened() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        _ = try await migrator.migrate(records: [record([("public.rtf", #"{\rtf1\ansi Meter reading}"#)])])

        let item = try #require(items(in: container).first)
        #expect(item.displayPreviewText == "Meter reading")
    }

    @Test("a rich-text record that holds no text is skipped, not imported empty")
    func migrate_richTextWithoutText_isSkipped() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        let summary = try await migrator.migrate(records: [record([("public.rtf", #"{\rtf1\ansi }"#)])])

        #expect(summary.skipped == 1)
        #expect(try items(in: container).isEmpty)
    }

    @Test("a link record is classified as a URL item")
    func migrate_linkRecord_classifiesAsURL() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)
        let record = PasteImportRecord(
            pinboard: "Useful Links",
            title: "example",
            timestamp: .now,
            sourceBundleID: nil,
            representations: [
                .init(
                    uti: "public.utf8-plain-text",
                    dataBase64: Data("https://example.com".utf8).base64EncodedString()
                ),
                .init(uti: "public.url", dataBase64: Data("https://example.com".utf8).base64EncodedString())
            ]
        )

        _ = try await migrator.migrate(records: [record])

        let item = try #require(items(in: container).first)
        #expect(item.type == .url)
    }

    @Test("a record copied from an excluded app is not imported, and is counted as skipped")
    func migrate_recordFromAnExcludedApp_isSkipped() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)
        let excluded = try #require(ExclusionRules.defaultExcludedBundleIDs.min())
        let record = PasteImportRecord(
            pinboard: nil, title: nil, timestamp: .now, sourceBundleID: excluded,
            representations: [.init(
                uti: "public.utf8-plain-text",
                dataBase64: Data("hunter2".utf8).base64EncodedString()
            )]
        )

        let summary = try await migrator.migrate(records: [record, textRecord(pinboard: "Commands", text: "kept")])

        #expect(summary.imported == 1)
        #expect(summary.skipped == 1)
        #expect(try items(in: container).map(\.displayPreviewText) == ["kept"])
    }

    @Test("an app the person added to the exclusion list is skipped too")
    func migrate_recordFromAUserExcludedApp_isSkipped() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        let summary = try await migrator.migrate(
            records: [textRecord(pinboard: "Commands", text: "from my private app")],
            exclusionRules: ExclusionRules(userAdditions: ["com.example.app"])
        )

        #expect(summary.imported == 0)
        #expect(summary.skipped == 1)
    }

    @Test("sensitive content is masked on import (routes through ingest)")
    func migrate_sensitiveContent_isMasked() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        _ = try await migrator.migrate(
            records: [textRecord(pinboard: "Useful Info", title: "card", text: "4111 1111 1111 1111")]
        )

        let item = try #require(items(in: container).first)
        #expect(item.sensitivity != nil)
        #expect(item.sensitivityMaskedPreview != nil)
    }

    @Test("re-running the same records does not duplicate items")
    func migrate_idempotent_noDuplicateItems() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)
        let records = [textRecord(pinboard: "Commands", text: "same content")]

        _ = try await migrator.migrate(records: records)
        _ = try await migrator.migrate(records: records)

        #expect(try items(in: container).count == 1)
    }

    @Test("duplicate content within one run is imported once")
    func migrate_duplicateWithinRun_importedOnce() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        let summary = try await migrator.migrate(records: [
            textRecord(pinboard: "Commands", text: "dup"),
            textRecord(pinboard: "Commands", text: "dup")
        ])

        #expect(summary.imported == 1)
        #expect(summary.skipped == 1)
        #expect(try items(in: container).count == 1)
    }

    @Test("a collection is reused across records, not duplicated")
    func migrate_reusesCollection() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        _ = try await migrator.migrate(records: [
            textRecord(pinboard: "Commands", text: "a"),
            textRecord(pinboard: "Commands", text: "b")
        ])

        #expect(try boards(in: container).count(where: { $0.name == "Commands" }) == 1)
    }

    @Test("a history record (no pinboard) is imported unpinned and in no collection")
    func migrate_historyRecord_isNotPinnedOrFiled() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)
        let record = PasteImportRecord(
            pinboard: nil, title: nil, timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            sourceBundleID: nil,
            representations: [.init(
                uti: "public.utf8-plain-text",
                dataBase64: Data("from history".utf8).base64EncodedString()
            )]
        )

        let summary = try await migrator.migrate(records: [record])

        #expect(summary.imported == 1)
        let item = try #require(items(in: container).first)
        #expect(!item.isPinned)
        #expect(item.collectionID == nil)
        #expect(try boards(in: container).isEmpty)
    }

    @Test("the first-run samples land as an unpinned welcome note and a pinned snippet without a Snippets collection")
    func migrate_firstRunSamples_areFiledAsDesigned() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let migrator = PasteMigrator(modelContainer: container)

        let summary = try await migrator.migrate(records: FirstRunSamples.records(shortcut: "\u{2318}\u{21E7}V"))

        #expect(summary.imported == 2)
        let stored = try items(in: container)
        let welcome = try #require(stored.first { $0.customTitle == FirstRunSamples.welcomeTitle })
        let snippet = try #require(stored.first { $0.customTitle == FirstRunSamples.snippetTitle })
        #expect(!welcome.isPinned && welcome.collectionID == nil)
        #expect(snippet.isPinned && snippet.isTemplate && snippet.collectionID == nil)
        #expect(try boards(in: container).isEmpty)
    }
}
