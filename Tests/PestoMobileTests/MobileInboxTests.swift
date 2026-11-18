// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The app adds what was shared to it")
@MainActor
struct MobileInboxTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    private func temporaryInbox() throws -> SharedInbox {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-mobile-inbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return SharedInbox(root: root)
    }

    @Test("becoming active publishes the key, and what the extension saved then becomes clips, a secret masked")
    func whenActive_thenSharedTextBecomesClips() async throws {
        let library = try await MobileTestLibrary()
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.root) }
        let keys = InboxKeyStore(secrets: MemorySecrets())

        #expect(throws: InboxError.noKey) { try inbox.deposit(#require(InboxItem.text("before Pesto ran"))) }
        _ = await library.state.drainInbox(inbox, keys: keys)
        #expect(try inbox.publishedKey() != nil)

        try inbox.deposit(#require(InboxItem.text("shared from Safari")))
        try inbox.deposit(#require(InboxItem.text(secret)))
        let report = try #require(await library.state.drainInbox(inbox, keys: keys))
        try await library.refreshed()

        #expect(report.added == 2)
        #expect(inbox.pendingFiles().isEmpty)
        #expect(library.store.items.contains { $0.displayPreviewText == "shared from Safari" })
        let hidden = try #require(library.store.items.first { $0.sensitivityRaw != nil })
        #expect(!hidden.gridPreview.contains(secret))
        #expect(library.state.notice == nil)
    }

    @Test("a file that will not open is removed and the person is told")
    func whenAFileDoesNotOpen_thenItIsRemovedAndReported() async throws {
        let library = try await MobileTestLibrary()
        let inbox = try temporaryInbox()
        defer { try? FileManager.default.removeItem(at: inbox.root) }
        let keys = InboxKeyStore(secrets: MemorySecrets())
        _ = await library.state.drainInbox(inbox, keys: keys)
        try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true)
        try Data("not sealed".utf8).write(
            to: inbox.directory.appendingPathComponent("x").appendingPathExtension(AppIdentity.inboxFileExtension)
        )

        let report = try #require(await library.state.drainInbox(inbox, keys: keys))

        #expect(report.discarded == 1)
        #expect(inbox.pendingFiles().isEmpty)
        #expect(library.state.notice?.isProblem == true)
    }
}
