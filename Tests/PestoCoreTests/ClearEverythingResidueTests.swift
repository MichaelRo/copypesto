// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

/// Clear Everything is the panic button. Deleting rows does not overwrite the pages they were in, and the write-ahead
/// log
/// keeps old frames until a checkpoint, so these tests read the real files after a clear.
@Suite("Clear Everything leaves nothing that could be read back", .serialized)
struct ClearEverythingResidueTests {
    private static let databaseFiles: Set<String> = ["clips.store", "clips.store-wal", "clips.store-shm"]

    private final class RowCounts: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [Int] = []

        var counts: [Int] {
            lock.withLock { recorded }
        }

        func record(_ container: ModelContainer) {
            let count = (try? ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>())) ?? -1
            lock.withLock { recorded.append(count) }
        }
    }

    private final class WipeTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var wiped = false

        var isWiped: Bool {
            lock.withLock { wiped }
        }

        func markWiped() {
            lock.withLock { wiped = true }
        }
    }

    private func sha(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func capture(_ text: String, bundleID: String) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            frontmostBundleID: bundleID, contentHash: sha(text)
        )
    }

    private func allBytes(under directory: URL) throws -> [(name: String, data: Data)] {
        let enumerator = try #require(FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        ))
        var files: [(String, Data)] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            try files.append((url.lastPathComponent, Data(contentsOf: url)))
        }
        return files
    }

    private func contains(_ needle: Data, in files: [(name: String, data: Data)]) -> Bool {
        files.contains { $0.data.range(of: needle) != nil }
    }

    /// Thirty-two bytes of ciphertext are random, so finding them is finding that clip's sealed bytes.
    private func needles(in container: ModelContainer) throws -> [Data] {
        let items = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        var found: [Data] = []
        for item in items {
            if let preview = item.previewCiphertext { found.append(preview.prefix(32)) }
            if let blob = item.blob { found.append(blob.encryptedData.prefix(32)) }
        }
        return found
    }

    /// Measured on macOS 27 (2026-10-16) before the key was replaced: after `clearEverything()` the sealed preview and
    /// blob bytes of the small clips were still in `clips.store` or its write-ahead log, and so were the plaintext
    /// fields (app names). Only the large clip's external file was gone. SwiftData offers no way to overwrite freed
    /// pages, so the sealed bytes are made unreadable by replacing the key; the plaintext fields are named in the
    /// guide.
    @Test("Clear Everything leaves no external blob file, and replaces the key once, after the rows are gone")
    func whenClearedEverything_thenNoExternalFileAndTheKeyIsReplacedLast() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-residue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try ModelContainer(
            for: ClipboardItem.self, ClipboardBlob.self, DeletedItemTombstone.self, Pinboard.self,
            configurations: ModelConfiguration(
                "clips", url: directory.appendingPathComponent("clips.store"), cloudKitDatabase: .none
            )
        )
        let rowsWhenRotated = RowCounts()
        let service = StorageService(modelContainer: container, environment: .testing {
            $0.keyRotator = { rowsWhenRotated.record(container) }
        })
        try await service.ingest(capture("quarterly notes \(UUID().uuidString)", bundleID: "com.example.small"))
        try await service.ingest(capture(
            String(repeating: "LARGE \(UUID().uuidString) ", count: 20_000), bundleID: "com.example.large"
        ))
        let sealed = try needles(in: container)
        let before = try allBytes(under: directory)
        #expect(sealed.count >= 3, "control: the clips should have sealed previews and blobs")
        #expect(sealed.allSatisfy { contains($0, in: before) }, "control: the scan must see the sealed bytes first")
        #expect(
            before.contains { !Self.databaseFiles.contains($0.name) },
            "control: the large clip should be in an external file"
        )

        let removed = try await service.clearEverything()
        let after = try allBytes(under: directory)

        #expect(removed == 2)
        #expect(rowsWhenRotated.counts == [0], "the key must be replaced once, after every row is deleted")
        #expect(!after.contains { !Self.databaseFiles.contains($0.name) }, "an external blob file survived")
    }

    @Test("a key that cannot be replaced does not undo the clear")
    func whenTheKeyCannotBeReplaced_thenTheClipsAreStillGone() async throws {
        struct Refused: Error {}
        let container = try ModelContainerSetup.makeInMemory()
        let service = StorageService(modelContainer: container, environment: .testing {
            $0.keyRotator = { throw Refused() }
        })
        try await service.ingest(capture("hello \(UUID().uuidString)", bundleID: "com.example.app"))

        let removed = try await service.clearEverything()

        #expect(removed == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>()) == 0)
    }

    @Test("clearEverything invokes wipeSuggestionLedger")
    func clearEverything_invokesWipeSuggestionLedger() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let tracker = WipeTracker()
        let service = StorageService(modelContainer: container, environment: .testing {
            $0.wipeSuggestionLedger = { tracker.markWiped() }
        })
        try await service.ingest(capture("clip", bundleID: "com.example.app"))
        _ = try await service.clearEverything()
        #expect(tracker.isWiped == true)
    }

    @Test("clearNonPinned in range all invokes wipeSuggestionLedger")
    func clearNonPinnedAll_invokesWipeSuggestionLedger() async throws {
        let container = try ModelContainerSetup.makeInMemory()
        let tracker = WipeTracker()
        let service = StorageService(modelContainer: container, environment: .testing {
            $0.wipeSuggestionLedger = { tracker.markWiped() }
        })
        try await service.ingest(capture("clip", bundleID: "com.example.app"))
        _ = try await service.clearNonPinned(in: .all)
        #expect(tracker.isWiped == true)
    }
}
