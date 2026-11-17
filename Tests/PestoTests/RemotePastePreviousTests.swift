// SPDX-License-Identifier: MIT
import AppKit
import Foundation
import PestoCore
import SwiftData
import Synchronization
import Testing
@testable import Pesto

private final class RemoteTestPasteboard: PasteboardReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _changeCount = 0
    private var _types: [NSPasteboard.PasteboardType] = []
    private var _urls: [URL] = []

    var changeCount: Int {
        lock.withLock { _changeCount }
    }

    func types() -> [NSPasteboard.PasteboardType] {
        lock.withLock { _types }
    }

    func setRemoteFileURL(_ url: URL) {
        lock.withLock {
            _changeCount += 1
            _types = [.fileURL, NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")]
            _urls = [url]
        }
    }

    func string(forType _: NSPasteboard.PasteboardType) -> String? {
        nil
    }

    func data(forType _: NSPasteboard.PasteboardType) -> Data? {
        nil
    }

    func fileURLs() -> [URL] {
        lock.withLock { _urls }
    }
}

private struct RemoteTestFrontmost: FrontmostAppProviding {
    func frontmostBundleID() async -> String? {
        "com.apple.Finder"
    }

    func recentBundleIDs(within _: TimeInterval) async -> [String] {
        []
    }
}

extension HostedGlobals {
    @Suite("RemotePastePrevious", .serialized)
    @MainActor
    final class RemotePastePreviousTests {
        @Test(
            "remote chmod-000 fileURL is blocked with zero reads, increments remoteBlocks, and pastes prior clip"
        )
        func whenRemoteCopyBlocked_thenIncrementsStatsAndPastesPriorLocalClip() async throws {
            let tempFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-remote-unreadable-\(UUID().uuidString).txt")
            try Data("secret".utf8).write(to: tempFile)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tempFile.path)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempFile.path)
                try? FileManager.default.removeItem(at: tempFile)
            }

            let board = RemoteTestPasteboard()
            let rules = ExclusionRules(keepsRemoteCopies: false)
            let watcher = PasteboardWatcher(
                pasteboard: board,
                frontmostProvider: RemoteTestFrontmost(),
                exclusionRules: rules
            )
            let statsStore = PrivacyStatsStore(defaults: AppDefaults.store)
            let beforeBlocks = statsStore.stats.remoteBlocks

            let capturedCount = Mutex(0)
            await watcher.onCapture { _ in capturedCount.withLock { $0 += 1 } }
            await watcher.onBlocked { statsStore.record($0) }

            board.setRemoteFileURL(tempFile)
            await watcher.tick()

            #expect(capturedCount.withLock { $0 } == 0)
            #expect(statsStore.stats.remoteBlocks == beforeBlocks + 1)
            let holdsUnrecorded = await watcher.boardHoldsUnrecordedCopy
            #expect(holdsUnrecorded)

            let schema = Schema([ClipboardItem.self, ClipboardBlob.self, Pinboard.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let localItem = ClipboardItem(
                type: .text,
                previewText: "prior local clip",
                contentHash: UUID().uuidString,
                byteSize: 16,
                deviceID: "local",
                sequenceNumber: 1
            )
            context.insert(localItem)
            try context.save()

            let delegate = AppDelegate()
            let previous = delegate.fetchPreviousClip(
                from: container,
                boardHoldsUnrecordedCopy: holdsUnrecorded
            )
            #expect(previous?.id == localItem.id)
            #expect(previous?.previewText == "prior local clip")
        }
    }
}
