// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PestoCore
@testable import PestoMobile

@Suite("The app keeps the widget's snapshot only while a widget is installed")
@MainActor
struct MobileWidgetTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    /// The Widgets setting, held by the test: read through `UserDefaults`, a missing value counts as on.
    private final class Switch {
        var isOn = true
    }

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

    @Test("a snapshot that cannot be written again is removed, never left with clips deleted or made secret since")
    func whenARewriteFails_thenTheOldSnapshotIsRemoved() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        try await library.add("written while unlocked")
        await library.state.refreshWidgetPresence()
        #expect(fixture.file.exists)
        let reloads = fixture.home.reloads

        fixture.secrets.refusesReads = true
        await library.state.writeWidget()

        #expect(!fixture.file.exists)
        #expect(fixture.home.reloads > reloads)
    }

    @Test("a deleted clip leaves the snapshot at once, not after the rewrite's pause")
    func whenAClipIsDeleted_thenItLeavesTheSnapshotAtOnce() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        let item = try await library.add("delete me")
        await library.state.refreshWidgetPresence()
        #expect(try fixture.texts() == ["delete me"])

        await library.state.delete([item.id])

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

    /// A collection made the way the library saves one, with `item` in it, so the save reaches the widget's observer.
    private func collection(
        _ name: String, holding item: ClipboardItem, in library: MobileTestLibrary
    ) throws
    -> (board: Pinboard, context: ModelContext) {
        let context = try ModelContext(#require(library.state.historyContainer))
        let board = Pinboard(name: name, symbolName: "briefcase", colorHex: "#2F8B4C", sortOrder: 0)
        context.insert(board)
        let id = item.id
        let member = try #require(context.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id }))
            .first)
        member.collectionID = board.id
        try context.saveOrRollback()
        return (board, context)
    }

    @Test("the widget's reader sees the collections the app wrote, and a renamed collection is written again")
    func whenACollectionChanges_thenTheWidgetSeesIt() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        let item = try await library.add("for the Work widget")
        let made = try collection("Work", holding: item, in: library)
        await library.state.refreshWidgetPresence()

        let reader = SharedFileKeyStore(secrets: fixture.secrets, account: AppIdentity.widgetKeyAccount)
        let snapshot = try #require(WidgetSnapshotReader.read(file: fixture.file, keys: reader))
        #expect(snapshot.collections.map(\.name) == ["Work"])
        #expect(snapshot.clips(inCollection: made.board.id).map(\.text) == ["for the Work widget"])

        made.board.name = "Office"
        try made.context.saveOrRollback()
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline, try fixture.read().collections.map(\.name) != ["Office"] {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(try fixture.read().collections.map(\.name) == ["Office"])
        let bytes = try Data(contentsOf: fixture.file.url)
        #expect(bytes.range(of: Data("Office".utf8)) == nil)
    }

    @Test("a link to a clip a collection widget showed that has since become secret only opens the library")
    func whenACollectionClipBecameSecret_thenItsLinkIsRefused() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let library = try await library(with: fixture)
        let item = try await library.add("harmless, in Work")
        let made = try collection("Work", holding: item, in: library)
        await library.state.refreshWidgetPresence()
        #expect(try fixture.read().clips(inCollection: made.board.id).map(\.id) == [item.id])

        #expect(try await library.service.updateText(id: item.id, text: secret) == .saved)
        try await library.refreshed()

        for action in WidgetLink.Action.allCases {
            #expect(library.state.open(WidgetLink.url(for: item.id, action: action)) == .ignored)
        }
        await library.state.writeWidget()
        #expect(try fixture.read().allClips.isEmpty)
    }

    @Test("a copy link copies a clip it may show and the library flashes it; anything else only opens the library")
    func whenACopyLinkIsOpened_thenOnlyAnEligibleClipIsCopied() async throws {
        let library = try await MobileTestLibrary()
        let shown = try await library.add("from the widget")
        try await library.service.ingest(#require(ClipCapture.text(secret)))
        let hidden = try await library.settle()
        #expect(hidden.sensitivityRaw != nil)

        #expect(library.state.open(WidgetLink.url(for: shown.id)) == .copied)
        #expect(library.state.linkedClip?.id == shown.id)
        #expect(library.state.linkedClip?.opensDetail == false)
        #expect(library.state.notice?.text == String(localized: "Copied"))

        let before = library.state.linkedClip
        for action in WidgetLink.Action.allCases {
            #expect(library.state.open(WidgetLink.url(for: hidden.id, action: action)) == .ignored)
            #expect(library.state.open(WidgetLink.url(for: UUID(), action: action)) == .ignored)
        }
        #expect(try library.state
            .open(#require(URL(string: "pesto://clip/\(shown.id.uuidString)?then=delete"))) == .ignored)
        #expect(try library.state.open(#require(URL(string: "pesto://paste?id=\(shown.id.uuidString)"))) == .ignored)
        #expect(try library.state.open(#require(URL(string: "pesto://open"))) == .ignored)
        #expect(library.state.linkedClip == before)
    }

    @Test("a show link opens the clip in Pesto without copying it")
    func whenAShowLinkIsOpened_thenTheDetailOpens() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("look at me")

        #expect(library.state.open(WidgetLink.url(for: item.id, action: .show)) == .shown)

        #expect(library.state.linkedClip?.opensDetail == true)
        #expect(library.state.notice == nil)
    }

    @Test("an open link hands only an http or https link clip to the browser; any other clip opens in Pesto")
    func whenAnOpenLinkIsOpened_thenOnlyTheWebLeavesPesto() async throws {
        let library = try await MobileTestLibrary()
        var opened: [URL] = []
        library.state.openExternally = { opened.append($0) }
        let web = try await library.add("https://copypesto.net/guide")
        let note = try await library.add("just a note")
        #expect(web.type == .url)

        #expect(try library.state.open(WidgetLink.url(for: web.id, action: .open)) == .openedInBrowser(
            #require(URL(string: "https://copypesto.net/guide"))
        ))
        #expect(library.state.open(WidgetLink.url(for: note.id, action: .open)) == .shown)
        #expect(opened.map(\.absoluteString) == ["https://copypesto.net/guide"])
        #expect(library.state.notice == nil)
    }

    @Test("the library goes back to All, out of a search; a copied clip's card flashes, a shown clip's detail opens")
    func whenTheLibraryShowsALinkedClip_thenItResets() {
        let model = LibraryModel()
        let id = UUID()
        model.filter.scope = .pinned
        model.query = "basil"
        model.isSearching = true
        model.openClipID = UUID()

        model.show(id, opensDetail: false)

        #expect(model.filter == LibraryFilter())
        #expect(model.query.isEmpty)
        #expect(!model.isSearching)
        #expect(model.openClipID == nil)
        #expect(model.flashedClipID == id)

        model.show(id, opensDetail: true)
        #expect(model.openClipID == id)
    }

    @Test(
        "an in-place copy writes the snapshot's whole text, a link as its address too, and remembers the tile briefly"
    )
    func whenATileCopiesInPlace_thenTheWholeTextIsWritten() {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let defaults = ThrowawayDefaults.make()
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        CopyClipIntent.write("https://copypesto.net/a", kind: .url, to: pasteboard)
        #expect(pasteboard.string == "https://copypesto.net/a")
        #expect(pasteboard.url?.absoluteString == "https://copypesto.net/a")
        #expect(Set(CopyClipIntent.item("javascript:alert(1)", kind: .url).keys) == [UTType.utf8PlainText.identifier])
        #expect(Set(CopyClipIntent.item("https://a.b", kind: .text).keys) == [UTType.utf8PlainText.identifier])

        WidgetCopyRecord.save(id, at: now, in: defaults)
        #expect(WidgetCopyRecord.recent(at: now + 1, in: defaults)?.id == id)
        #expect(WidgetCopyRecord.recent(at: now + WidgetSnapshotPolicy.copiedFeedback, in: defaults) == nil)
        #expect(WidgetCopyRecord.recent(at: now - 1, in: defaults) == nil)
    }

    @Test("when widgetsEnabled is false, refreshing or writing removes the snapshot and key")
    func whenWidgetsDisabled_thenSnapshotAndKeyAreRemoved() async throws {
        let fixture = try fixture(installed: true)
        defer { try? FileManager.default.removeItem(at: fixture.file.root) }
        let setting = Switch()
        var target = fixture.target
        target.isEnabled = { setting.isOn }
        let library = try await MobileTestLibrary()
        library.state.widget = target
        try await library.add("12 Basil Lane")

        await library.state.refreshWidgetPresence()
        #expect(fixture.file.exists)

        setting.isOn = false
        await library.state.writeWidget()

        #expect(!fixture.file.exists)
        #expect(try target.keys.key() == nil)
    }

    @Test("WidgetTarget matches both Home Screen and Lock Screen widget kinds")
    func whenWidgetKindsChecked_thenIncludesLockScreenWidget() {
        #expect(WidgetTarget.matchesInstalledKind(AppIdentity.widgetKind))
        #expect(WidgetTarget.matchesInstalledKind(AppIdentity.lockScreenWidgetKind))
        #expect(!WidgetTarget.matchesInstalledKind("other.widget"))
    }

    @Test("WidgetSnapshotReader caches unchanged snapshots by stamp and invalidates on rewrite or delete")
    func whenSnapshotFileUnchangedRewrittenOrDeleted_thenReaderCachesAndInvalidates() async throws {
        WidgetSnapshotReader.clearCache()
        let fixture = try fixture(installed: true)
        defer {
            WidgetSnapshotReader.clearCache()
            try? FileManager.default.removeItem(at: fixture.file.root)
        }
        let library = try await library(with: fixture)
        try await library.add("first cached clip")
        await library.state.refreshWidgetPresence()

        let reader = SharedFileKeyStore(secrets: fixture.secrets, account: AppIdentity.widgetKeyAccount)
        let first = try #require(WidgetSnapshotReader.read(file: fixture.file, keys: reader))
        let second = try #require(WidgetSnapshotReader.read(file: fixture.file, keys: reader))
        #expect(first == second)

        try await Task.sleep(for: .milliseconds(50))
        try await library.add("second updated clip")
        await library.state.writeWidget()
        let updated = try #require(WidgetSnapshotReader.read(file: fixture.file, keys: reader))
        #expect(updated.clips.map(\.text).contains("second updated clip"))

        fixture.file.remove()
        #expect(WidgetSnapshotReader.read(file: fixture.file, keys: reader) == nil)
    }
}
