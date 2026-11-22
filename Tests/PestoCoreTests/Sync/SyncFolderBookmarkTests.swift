// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

/// Bookmarks that are only the path, with a switch for a stale link and a count of every start and stop.
final class FakeBookmarks: SecurityScopedBookmarks, @unchecked Sendable {
    private let lock = NSLock()
    private var starts: [URL: Int] = [:]
    private var stops: [URL: Int] = [:]
    private var bookmarksMade = 0
    var isStale = false
    var grantsScope = true
    var refusesBookmark = false

    func bookmark(for url: URL) throws -> Data {
        try lock.withLock {
            guard !refusesBookmark else { throw CocoaError(.fileReadNoPermission) }
            bookmarksMade += 1
            isStale = false
            return Data(url.path.utf8)
        }
    }

    var bookmarkCount: Int {
        lock.withLock { bookmarksMade }
    }

    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8), path.hasPrefix("/") else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (URL(fileURLWithPath: path, isDirectory: true), lock.withLock { isStale })
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock {
            guard grantsScope else { return false }
            starts[url.standardizedFileURL, default: 0] += 1
            return true
        }
    }

    func stopAccessing(_ url: URL) {
        lock.withLock { stops[url.standardizedFileURL, default: 0] += 1 }
    }

    func isReachableFolder(_ url: URL) -> Bool {
        SystemBookmarks().isReachableFolder(url)
    }

    var held: Int {
        lock.withLock { starts.values.reduce(0, +) - stops.values.reduce(0, +) }
    }

    var startCount: Int {
        lock.withLock { starts.values.reduce(0, +) }
    }
}

@Suite("The sync folder an iPhone was given: a bookmark, opened and closed in balance")
@MainActor
struct SyncFolderBookmarkTests {
    let picked: URL
    let defaults = ThrowawayDefaults.make()

    init() throws {
        picked = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-bookmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
    }

    @Test("nothing is chosen until the person picks a folder")
    func whenNothingWasPicked_thenThereIsNoFolder() {
        let source = BookmarkedSyncFolder(defaults: defaults, bookmarks: FakeBookmarks())
        #expect(!source.hasChosenFolder)
        #expect(source.resolve() == .notChosen)
    }

    @Test("a picked folder is saved as a bookmark setting and resolves to the Pesto Sync folder inside it")
    func whenAFolderIsPicked_thenItIsSavedAndResolvesAgain() throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let bookmarks = FakeBookmarks()
        let source = BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks)

        let root = try source.choose(picked)

        #expect(root.lastPathComponent == BookmarkedSyncFolder.folderName)
        #expect(root.deletingLastPathComponent().standardizedFileURL == picked.standardizedFileURL)
        #expect(!defaults.value(for: Setting.syncFolderBookmark).isEmpty)
        #expect(source.hasChosenFolder)
        source.relinquish()

        let later = BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks)
        guard case let .ready(again) = later.resolve() else {
            Issue.record("the saved bookmark should resolve")
            return
        }
        #expect(again.standardizedFileURL == root.standardizedFileURL)
        later.relinquish()
        #expect(bookmarks.held == 0)
    }

    @Test("a folder that already is a sync folder, or is named Pesto Sync, is used as it is")
    func whenThePickedFolderIsASyncFolder_thenItIsTheRoot() throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let named = picked.appendingPathComponent(BookmarkedSyncFolder.folderName, isDirectory: true)
        #expect(BookmarkedSyncFolder.syncRoot(forPicked: named) == named)
        try FileManager.default.createDirectory(
            at: SyncFolderLayout(root: picked).devices, withIntermediateDirectories: true
        )
        #expect(BookmarkedSyncFolder.syncRoot(forPicked: picked) == picked)
    }

    @Test("a stale bookmark that cannot be made again asks for the folder again and holds nothing open")
    func whenTheBookmarkIsStaleAndCannotBeRenewed_thenTheFolderNeedsRepair() throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let bookmarks = FakeBookmarks()
        let source = BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks)
        _ = try source.choose(picked)
        source.relinquish()
        bookmarks.isStale = true
        bookmarks.refusesBookmark = true

        #expect(source.resolve() == .needsRepair(.stale))
        #expect(bookmarks.held == 0)
    }

    @Test("a stale bookmark that still opens the folder is made again and stored, and sync goes on")
    func whenTheBookmarkIsStaleButOpens_thenItIsRenewedAndTheFolderIsReady() throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let bookmarks = FakeBookmarks()
        let source = BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks)
        let root = try source.choose(picked)
        source.relinquish()
        let made = bookmarks.bookmarkCount
        bookmarks.isStale = true

        #expect(source.resolve() == .ready(root))
        #expect(bookmarks.bookmarkCount == made + 1)
        #expect(bookmarks.held == 1)
        source.relinquish()

        let later = BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks)
        #expect(later.resolve() == .ready(root), "the renewed bookmark is the one stored")
        later.relinquish()
        #expect(bookmarks.held == 0)
    }

    @Test("a bookmark that does not resolve asks for the folder again")
    func whenTheBookmarkIsDamaged_thenTheFolderNeedsRepair() {
        defaults.set("not base64 at all \u{1F600}", for: Setting.syncFolderBookmark)
        let source = BookmarkedSyncFolder(defaults: defaults, bookmarks: FakeBookmarks())
        #expect(source.resolve() == .needsRepair(.unresolvable))
        defaults.set(Data("relative/path".utf8).base64EncodedString(), for: Setting.syncFolderBookmark)
        #expect(source.resolve() == .needsRepair(.unresolvable))
    }

    @Test("a folder that was deleted asks for the folder again, and its access is given back")
    func whenTheFolderIsGone_thenTheFolderNeedsRepair() throws {
        let bookmarks = FakeBookmarks()
        let source = BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks)
        _ = try source.choose(picked)
        source.relinquish()
        try FileManager.default.removeItem(at: picked)

        #expect(source.resolve() == .needsRepair(.unreachable))
        #expect(bookmarks.held == 0)
    }

    @Test("access is started once while the folder is open and stopped once when it is given back")
    func whenOpenedAndRelinquished_thenAccessIsBalanced() throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let bookmarks = FakeBookmarks()
        let source = BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks)
        _ = try source.choose(picked)
        #expect(bookmarks.held == 1)
        _ = source.resolve()
        _ = source.resolve()
        #expect(bookmarks.held == 1, "resolving an open folder again does not start it again")
        source.relinquish()
        source.relinquish()
        #expect(bookmarks.held == 0)

        for _ in 0..<3 {
            _ = source.resolve()
            source.relinquish()
        }
        #expect(bookmarks.held == 0)
        #expect(bookmarks.startCount == 5)
    }

    @Test("choosing another folder gives the first one back")
    func whenAnotherFolderIsChosen_thenTheFirstIsReleased() throws {
        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-bookmark-other-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: picked)
            try? FileManager.default.removeItem(at: other)
        }
        let bookmarks = FakeBookmarks()
        let source = BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks)
        _ = try source.choose(picked)
        let root = try source.choose(other)
        #expect(root.deletingLastPathComponent().standardizedFileURL == other.standardizedFileURL)
        #expect(bookmarks.held == 1)
        source.relinquish()
        #expect(bookmarks.held == 0)
    }

    @Test("a folder that needs no scope (inside the app's own container) is never stopped")
    func whenNoScopeIsGranted_thenNothingIsStopped() throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let bookmarks = FakeBookmarks()
        bookmarks.grantsScope = false
        let source = BookmarkedSyncFolder(defaults: defaults, bookmarks: bookmarks)
        _ = try source.choose(picked)
        source.relinquish()
        #expect(bookmarks.held == 0)
    }

    @Test("the system's own bookmark of a real folder resolves back to it")
    func whenTheSystemMakesTheBookmark_thenItResolves() throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let source = BookmarkedSyncFolder(defaults: defaults)
        let root = try source.choose(picked)
        source.relinquish()
        guard case let .ready(again) = source.resolve() else {
            Issue.record("a real bookmark should resolve")
            return
        }
        #expect(again.lastPathComponent == root.lastPathComponent)
        #expect(
            again.deletingLastPathComponent().resolvingSymlinksInPath().path
                == picked.resolvingSymlinksInPath().path
        )
        source.relinquish()
    }

    @Test("a picked folder containing a nested Pesto/Pesto Sync folder resolves directly to it")
    func whenNestedUnderPestoFolder_thenSyncRootTracesPestoSubfolder() throws {
        defer { try? FileManager.default.removeItem(at: picked) }
        let nested = picked
            .appendingPathComponent("Pesto", isDirectory: true)
            .appendingPathComponent(BookmarkedSyncFolder.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let resolved = BookmarkedSyncFolder.syncRoot(forPicked: picked)
        #expect(resolved.resolvingSymlinksInPath().path == nested.resolvingSymlinksInPath().path)
    }
}
