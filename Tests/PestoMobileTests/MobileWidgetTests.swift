// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("The app keeps the widget's snapshot only while a widget is installed")
@MainActor
struct MobileWidgetTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    private final class Home {
        var installed: Bool
        var reloads = 0
        var asked = 0

        init(_ installed: Bool) {
            self.installed = installed
        }
    }

    @MainActor
    private struct Fixture {
        let target: WidgetTarget
        let secrets: MemorySecrets
        let home: Home

        var file: SealedGroupFile {
            target.file
        }

        func read() throws -> WidgetSnapshot {
            try file.read(WidgetSnapshot.self, with: #require(try target.keys.key()))
        }

        func texts() throws -> [String] {
            try read().clips.map(\.text)
        }
    }

    private func fixture(installed: Bool) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-mobile-widget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let secrets = MemorySecrets()
        let home = Home(installed)
        let target = WidgetTarget(
            file: SealedGroupFile(root: root, format: .widgetSnapshot),
            keys: SharedFileKeyStore(secrets: secrets, account: AppIdentity.widgetKeyAccount),
            isInstalled: {
                home.asked += 1
                return home.installed
            },
            reload: { home.reloads += 1 }
        )
        return Fixture(target: target, secrets: secrets, home: home)
    }

    private func library(with fixture: Fixture) async throws -> MobileTestLibrary {
        let library = try await MobileTestLibrary()
        library.state.widget = fixture.target
        return library
    }

    /// The snapshot's texts once the pending rewrite has run.
    private func written(_ fixture: Fixture, count: Int) async throws -> [String] {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            let texts = try fixture.texts()
            if texts.count >= count { return texts }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try fixture.texts()
    }

    @Test("with no widget installed there is no file and the Keychain is never asked")
    func whenNoWidget_thenNoFileAndNoKey() async throws {
        let fixture = try fixture(installed: false)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        try await library.add("a note")

        await library.state.refreshWidgetPresence()
        library.state.widgetHistoryChanged()
        await library.state.writeWidget()

        #expect(fixture.home.asked == 1)
        #expect(!fixture.file.exists)
        #expect(fixture.secrets.readCount == 0)
        #expect(fixture.home.reloads == 0)
    }

    @Test("installed, the snapshot holds the newest clips that may be shown, and the widget is reloaded")
    func whenInstalled_thenTheSnapshotIsWritten() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        try await library.add("12 Basil Lane")
        try await library.service.ingest(#require(ClipCapture.text(secret)))
        try await library.refreshed()

        await library.state.refreshWidgetPresence()

        #expect(try fixture.texts() == ["12 Basil Lane"])
        #expect(try fixture.read().theme.lightGround == WidgetSnapshot.Theme.brand.lightGround)
        #expect(fixture.home.reloads >= 1)
        let bytes = try Data(contentsOf: fixture.file.url)
        #expect(bytes.range(of: Data("Basil".utf8)) == nil)
    }

    @Test("a change to the history is written after a moment")
    func whenTheHistoryChanges_thenTheSnapshotFollows() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        await library.state.refreshWidgetPresence()
        #expect(try fixture.texts().isEmpty)

        try await library.add("first")
        #expect(try await written(fixture, count: 1) == ["first"])
        try await library.add("second")
        #expect(try await written(fixture, count: 2) == ["second", "first"])
    }

    @Test("Clear History empties the snapshot at once and reloads the widget")
    func whenTheHistoryIsCleared_thenTheSnapshotIsEmpty() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        try await library.add("to be cleared")
        await library.state.refreshWidgetPresence()
        #expect(try fixture.texts().count == 1)
        let reloads = fixture.home.reloads

        await library.state.clearHistory()

        #expect(try fixture.texts().isEmpty)
        #expect(fixture.home.reloads > reloads)
    }

    @Test("a clip edited into a secret leaves the snapshot on the next write")
    func whenAClipBecomesSecret_thenItLeavesTheSnapshot() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        let item = try await library.add("harmless")
        await library.state.refreshWidgetPresence()
        #expect(try fixture.texts() == ["harmless"])

        #expect(try await library.service.updateText(id: item.id, text: secret) == .saved)
        try await library.refreshed()
        await library.state.writeWidget()

        #expect(try fixture.texts().isEmpty)
    }

    @Test("the last widget removed takes the file and the key with it")
    func whenTheWidgetIsRemoved_thenTheFileAndKeyGo() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        try await library.add("kept for a while")
        await library.state.refreshWidgetPresence()
        #expect(fixture.file.exists)

        fixture.home.installed = false
        library.state.didLeaveForeground()
        try await Task.sleep(for: .milliseconds(200))
        await library.state.refreshWidgetPresence()

        #expect(!fixture.file.exists)
        #expect(try fixture.target.keys.key() == nil)
    }

    @Test("the widget's read path opens what the app wrote; the quick-insert key does not")
    func whenTheWidgetReads_thenItOpensTheAppsSnapshot() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        try await library.add("for the Home Screen")
        await library.state.refreshWidgetPresence()

        let reader = SharedFileKeyStore(secrets: fixture.secrets, account: AppIdentity.widgetKeyAccount)
        let snapshot = WidgetSnapshotReader.read(
            file: SealedGroupFile(root: fixture.file.root, format: .widgetSnapshot),
            keys: reader
        )
        let other = QuickInsertKeyStore(secrets: fixture.secrets)
        _ = try other.loadOrCreate()
        let wrong = SharedFileKeyStore(secrets: fixture.secrets, account: AppIdentity.quickInsertKeyAccount)

        #expect(snapshot?.clips.map(\.text) == ["for the Home Screen"])
        #expect(WidgetSnapshotReader.read(file: fixture.file, keys: wrong) == nil)
    }

    @Test("a widget link copies a clip it may show and the library shows it; anything else only opens the library")
    func whenALinkIsOpened_thenOnlyAnEligibleClipIsCopied() async throws {
        let library = try await MobileTestLibrary()
        let shown = try await library.add("from the widget")
        try await library.service.ingest(#require(ClipCapture.text(secret)))
        let hidden = try await library.settle()
        #expect(hidden.sensitivityRaw != nil)

        #expect(library.state.open(WidgetLink.url(for: shown.id)))
        #expect(library.state.linkedClip?.id == shown.id)
        #expect(library.state.notice?.text == String(localized: "Copied"))

        let before = library.state.linkedClip
        #expect(!library.state.open(WidgetLink.url(for: hidden.id)))
        #expect(!library.state.open(WidgetLink.url(for: UUID())))
        #expect(try !library.state.open(#require(URL(string: "pesto://clip/\(shown.id.uuidString)?then=delete"))))
        #expect(try !library.state.open(#require(URL(string: "pesto://paste?id=\(shown.id.uuidString)"))))
        #expect(library.state.linkedClip == before)
    }

    @Test("the library goes back to All, out of a search and an open clip, and flashes the linked card")
    func whenTheLibraryShowsALinkedClip_thenItResets() {
        let model = LibraryModel()
        let id = UUID()
        model.filter.scope = .pinned
        model.query = "basil"
        model.isSearching = true
        model.openClipID = UUID()

        model.show(id)

        #expect(model.filter == LibraryFilter())
        #expect(model.query.isEmpty)
        #expect(!model.isSearching)
        #expect(model.openClipID == nil)
        #expect(model.flashedClipID == id)
    }
}
