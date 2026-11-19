// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("pesto:// links run against the host", .serialized)
@MainActor
struct AutomationURLHandlerTests {
    @MainActor
    private final class SpyHost: AutomationHost {
        var isHistoryLocked = false
        var isContentCovered = false
        var historyContainer: ModelContainer?
        var events: [String] = []

        func showShelf() {
            events.append("show")
        }

        func togglePinnedWindow() {
            events.append("list")
        }

        func search(for text: String) {
            events.append("search:\(text)")
        }

        func selectCollection(_ id: UUID?) {
            events.append("collection:\(id?.uuidString ?? "none")")
        }

        func paste(_ item: ClipboardItem) {
            events.append("paste:\(item.displayPreviewText)")
        }

        func togglePin(id: UUID) async {
            events.append("pin:\(id.uuidString)")
        }

        func requestClear(_ range: ClearRange) {
            events.append("clear:\(range.rawValue)")
        }

        func copyClip(_ item: ClipboardItem) {
            events.append("copy:\(item.displayPreviewText)")
        }

        func openWebLink(_ url: URL) {
            events.append("browse:\(url.absoluteString)")
        }
    }

    private let container: ModelContainer
    private let service: StorageService
    private let host = SpyHost()
    private let handler: AutomationURLHandler
    private let clock = TestClock()

    @MainActor
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    init() throws {
        container = try ModelContainerSetup.makeInMemory()
        service = StorageService(modelContainer: container)
        host.historyContainer = container
        handler = AutomationURLHandler(host: host, now: { [clock] in clock.now })
    }

    private func ingest(_ text: String) async throws -> UUID {
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        try await service.ingest(PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: Date(timeIntervalSince1970: 1000), contentHash: hash
        ))
        let items = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        return try #require(items.first).id
    }

    private func run(_ request: AutomationRequest) async {
        await handler.run(request)?.value
    }

    @Test("open and list reach the windows, and a link of another kind does nothing")
    func whenWindowsAreAsked_thenTheHostOpensThem() throws {
        try handler.handle(#require(URL(string: "pesto://open")))
        try handler.handle(#require(URL(string: "pesto://list")))
        try handler.handle(#require(URL(string: "https://open")))

        #expect(host.events == ["show", "list"])
    }

    @Test("search fills the field behind the shelf, and with no text only opens the shelf")
    func whenSearch_thenShelfAndText() async {
        await run(.search("invoice"))
        await run(.search(nil))

        #expect(host.events == ["show", "search:invoice", "show"])
    }

    @Test("while locked, search opens the lock screen and sets no text")
    func whenLockedSearch_thenOnlyTheShelf() async {
        host.isHistoryLocked = true

        await run(.search("invoice"))

        #expect(host.events == ["show"])
    }

    @Test("paste hands the stored clip to the host")
    func whenPaste_thenTheClipIsPasted() async throws {
        let id = try await ingest("hello world")

        await run(.paste(id))

        #expect(host.events == ["paste:hello world"])
    }

    @Test("paste of an id the store does not have does nothing")
    func whenPasteUnknownId_thenNothing() async {
        await run(.paste(UUID()))

        #expect(host.events.isEmpty)
    }

    @Test("pin goes through the host, and not while locked")
    func whenPin_thenToggledUnlessLocked() async {
        let id = UUID()
        await run(.pin(id))
        host.isHistoryLocked = true
        await run(.pin(UUID()))

        #expect(host.events == ["pin:\(id.uuidString)"])
    }

    @Test("a collection is found by name, ignoring case, and an unknown name clears the selection")
    func whenCollection_thenSelectedByName() async throws {
        let board = Pinboard(name: "Work", symbolName: "folder", colorHex: "#4C8DFF", sortOrder: 0)
        let context = ModelContext(container)
        context.insert(board)
        try context.save()

        await run(.collection("wORK"))
        await run(.collection("Nowhere"))

        #expect(host.events == ["collection:\(board.id.uuidString)", "show", "collection:none", "show"])
    }

    @Test("clear asks the host to confirm; the host decides")
    func whenClear_thenRequestedWithTheRange() async {
        await run(.clear(.lastHour))

        #expect(host.events == ["clear:lastHour"])
    }

    @Test("a web page cannot raise the clear confirmation again and again")
    func whenClearIsRepeated_thenOnlyTheFirstAsks() async {
        await run(.clear(.all))
        clock.now.addTimeInterval(5)
        await run(.clear(.all))
        clock.now.addTimeInterval(60)
        await run(.clear(.lastHour))

        #expect(host.events == ["clear:all", "clear:lastHour"])
    }

    @Test("summary shows the shelf searching for the clip's first 40 characters")
    func whenSummary_thenSearchesForThePrefix() async throws {
        let text = String(repeating: "abcdefghij", count: 6)
        let id = try await ingest(text)

        await run(.summary(id))

        #expect(host.events == ["show", "search:\(text.prefix(40))"])
    }

    @Test("summary of a short clip does nothing")
    func whenSummaryOfAShortClip_thenNothing() async throws {
        let id = try await ingest("short")

        await run(.summary(id))

        #expect(host.events.isEmpty)
    }

    @Test("summary of a secret does nothing")
    func whenSummaryOfASecret_thenNothing() async throws {
        let id = try await ingest("4111 1111 1111 1111 and more words")
        let context = ModelContext(container)
        let item = try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id })
        #expect(item.sensitivityRaw != nil, "the fixture is not detected as sensitive")

        await run(.summary(id))

        #expect(host.events.isEmpty)
    }

    @Test("while locked, paste, collection and summary open the lock screen and touch nothing", arguments: [0, 1, 2])
    func whenLocked_thenOnlyTheShelf(which: Int) async throws {
        let id = try await ingest("something long enough to summarise")
        host.isHistoryLocked = true
        host.events = []
        let requests: [AutomationRequest] = [.paste(id), .collection("Work"), .summary(id)]

        await run(requests[which])

        #expect(host.events == ["show"])
    }

    @Test("with no history container, store-backed links do nothing")
    func whenNoContainer_thenNothing() async {
        host.historyContainer = nil

        await run(.paste(UUID()))
        await run(.collection("Work"))
        await run(.summary(UUID()))

        #expect(host.events.isEmpty)
    }

    @Test("a widget's link copies, shows or opens an eligible clip, through the host")
    func whenAWidgetLinkNamesAnEligibleClip_thenTheHostActs() async throws {
        let text = try await ingest("Lunch at noon on Thursday")
        await run(.widget(.init(id: text, action: .copy)))
        await run(.widget(.init(id: text, action: .show)))
        await run(.widget(.init(id: text, action: .open)))

        #expect(host.events == [
            "copy:Lunch at noon on Thursday", "show", "search:Lunch at noon on Thursday", "show",
            "search:Lunch at noon on Thursday"
        ])
    }

    @Test("Open hands a link clip that is one web address to the browser")
    func whenOpenNamesALinkClip_thenTheBrowserGetsIt() async throws {
        let id = try await ingest("https://example.com/menu")
        let item = try #require(ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).first { $0.id == id })
        try #require(item.type == .url)

        await run(.widget(.init(id: id, action: .open)))

        #expect(host.events == ["browse:https://example.com/menu"])
    }

    @Test("a secret, an unknown id or a locked history only opens the shelf")
    func whenTheClipMayNotLeave_thenOnlyTheShelf() async throws {
        let secret = try await ingest("4111 1111 1111 1111 and more words")
        await run(.widget(.init(id: secret, action: .copy)))
        await run(.widget(.init(id: UUID(), action: .copy)))
        #expect(host.events == ["show", "show"])

        let text = try await ingest("an ordinary note")
        host.events = []
        host.isHistoryLocked = true
        await run(.widget(.init(id: text, action: .copy)))
        #expect(host.events == ["show"])
    }

    @Test("while clip contents are covered, Show and Open only open the shelf; Copy still copies (ADR 0003)")
    func whenContentsAreCovered_thenShowAndOpenRevealNothing() async throws {
        let text = try await ingest("Lunch at noon on Thursday")
        let link = try await ingest("https://example.com/menu")
        host.events = []
        host.isContentCovered = true

        await run(.widget(.init(id: text, action: .show)))
        await run(.widget(.init(id: link, action: .open)))
        await run(.widget(.init(id: link, action: .show)))
        await run(.widget(.init(id: text, action: .copy)))

        #expect(host.events == ["show", "show", "show", "copy:Lunch at noon on Thursday"])
    }
}
