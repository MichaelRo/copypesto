// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import XCTest
@testable import Pesto

/// What Undo costs (ADR 0008), measured over a file-backed store that already holds 5,000 clips. `make bench-undo`
/// runs this class and `UndoHistoryMemoryTests` and prints the `PERF` lines. The budgets are asserted on a developer
/// Mac only (`RunEnvironment.isCI`); the structural assertions (what is held, what is restored) run everywhere.
@MainActor
private func makeFileBackedContainer(for test: XCTestCase, seededWith count: Int) throws -> ModelContainer {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pesto-undo-perf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let container = try ModelContainerSetup.openSynced(
        cloudKitEnabled: false, storeURL: directory.appendingPathComponent("clips.store")
    )
    let context = ModelContext(container)
    let encryption = BlobEncryption()
    for index in 0..<count {
        let item = ClipboardItem(
            type: .text, previewText: "", contentHash: "seed-hash-\(index)", byteSize: 80,
            deviceID: "perf", sequenceNumber: Int64(index)
        )
        let envelope = try encryption.encrypt(Data("Seeded clip number \(index), a line of ordinary text.".utf8))
        item.previewCiphertext = envelope.ciphertext
        item.previewNonce = envelope.nonce
        context.insert(item)
    }
    try context.save()
    return container
}

@MainActor
final class UndoPerformanceTests: XCTestCase {
    /// Overhead of recording a delete, over the same delete without it, for the largest batch Undo holds.
    private static let recordOverheadBudgetMilliseconds = 100.0
    private static let restoreBudgetMilliseconds = 100.0
    private static let editOverheadBudgetMilliseconds = 5.0
    private static let reorderBudgetMilliseconds = 100.0

    private let clock = ContinuousClock()
    private var nextTimestamp = Date.now.addingTimeInterval(3600)

    private func makeStore() throws -> ModelContainer {
        try makeFileBackedContainer(for: self, seededWith: 5000)
    }

    private func makeService(on container: ModelContainer, history: UndoHistory) -> StorageService {
        StorageService(modelContainer: container, environment: .testing { $0.undoHistory = history })
    }

    /// Saves `count` fresh two-kilobyte texts, newer than everything else, and returns their ids.
    private func ingest(_ count: Int, tag: String, into service: StorageService, container: ModelContainer)
        async throws
        -> [UUID]
    {
        let body = String(repeating: "lorem ipsum dolor sit amet ", count: 75)
        for index in 0..<count {
            let text = "\(tag)-\(index) \(body)"
            nextTimestamp = nextTimestamp.addingTimeInterval(1)
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
                timestamp: nextTimestamp, contentHash: "perf-\(tag)-\(index)"
            ))
        }
        var newest = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        newest.fetchLimit = count
        return try ModelContext(container).fetch(newest).map(\.id)
    }

    private func milliseconds(_ body: () async throws -> Void) async rethrows -> Double {
        let start = clock.now
        try await body()
        return PerfReport.milliseconds(clock.now - start)
    }

    func test_whenDeletingClips_thenRecordingCostsLittleAndUndoIsFast() async throws {
        let container = try makeStore()
        let history = UndoHistory()
        let service = makeService(on: container, history: history)

        for count in [1, 50, 200] {
            let plainIDs = try await ingest(count, tag: "plain\(count)", into: service, container: container)
            let plain = try await milliseconds {
                try await service.deleteItems(ids: plainIDs, reason: .user, recordsUndo: false)
            }
            let keptIDs = try await ingest(count, tag: "kept\(count)", into: service, container: container)
            let recorded = try await milliseconds { try await service.deleteItems(ids: keptIDs, reason: .user) }
            let held = history.heldBytes
            let undone = try await milliseconds { try await service.undo() }
            let restoredCount = try ModelContext(container).fetchCount(FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { keptIDs.contains($0.id) }
            ))
            let redone = try await milliseconds { try await service.redo() }
            try await service.undo()

            let overhead = recorded - plain
            func ms(_ value: Double) -> String {
                String(format: "%.1f", value)
            }
            PerfReport.emit(
                "undo delete \(count) clips: \(ms(plain)) ms plain, \(ms(recorded)) ms recorded " +
                    "(+\(ms(overhead))), undo \(ms(undone)), redo \(ms(redone)), held \(held / 1024) KB"
            )
            XCTAssertEqual(restoredCount, count, "undo of \(count) clips restored \(restoredCount)")
            XCTAssertGreaterThan(held, 0, "the delete of \(count) clips was not held")
            if !RunEnvironment.isCI {
                XCTAssertLessThan(overhead, Self.recordOverheadBudgetMilliseconds, "recording \(count) clips")
                XCTAssertLessThan(undone, Self.restoreBudgetMilliseconds, "undo of \(count) clips")
            }
            history.clear()
        }
    }

    func test_whenEditingClips_thenRecordingCostsLittle() throws {
        let container = try makeStore()
        let context = ModelContext(container)
        var firstItems = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.sequenceNumber)])
        firstItems.fetchLimit = 200
        let items = try context.fetch(firstItems)
        let history = UndoHistory()
        func editor(_ history: UndoHistory?) -> ClipEditor {
            ClipEditor(
                context: context, historyStore: nil, report: { _, work in try? work() }, didEdit: {},
                undoHistory: history
            )
        }

        var counter = 0
        let plain = PerfReport.time(runs: 15) {
            counter += 1
            editor(nil).edit(items[0]) { $0.customTitle = "title \(counter)" }
        }
        let recorded = PerfReport.time(runs: 15) {
            counter += 1
            editor(history).edit(items[0]) { $0.customTitle = "title \(counter)" }
        }
        PerfReport.emit("undo edit one clip: \(plain.text) plain; \(recorded.text) recorded")

        let reorder = PerfReport.time(runs: 3) {
            counter += 1
            editor(history).edit(items) { $0.collectionOrder = ($0.collectionOrder ?? 0) + counter }
        }
        PerfReport.emit("undo reorder 200 clips: \(reorder.text); held \(history.heldBytes / 1024) KB")

        XCTAssertGreaterThan(history.entryCount, 0, "edits were not recorded")
        if !RunEnvironment.isCI {
            XCTAssertLessThan(recorded.median - plain.median, Self.editOverheadBudgetMilliseconds, "one edit")
            XCTAssertLessThan(reorder.median, Self.reorderBudgetMilliseconds, "a reorder of 200 clips")
        }
    }

    func test_whenTheStackIsFull_thenIngestIsNoSlower() async throws {
        let container = try makeStore()
        let emptyHistory = UndoHistory()
        let emptyService = makeService(on: container, history: emptyHistory)
        let empty = try await ingestTimes(20, tag: "empty", into: emptyService, container: container)

        let fullHistory = UndoHistory()
        let fullService = makeService(on: container, history: fullHistory)
        for round in 0..<UndoPolicy.maxEntries {
            let ids = try await ingest(1, tag: "fill\(round)", into: fullService, container: container)
            try await fullService.deleteItems(ids: ids, reason: .user)
        }
        XCTAssertEqual(fullHistory.entryCount, UndoPolicy.maxEntries)
        let full = try await ingestTimes(20, tag: "full", into: fullService, container: container)

        PerfReport.emit("undo ingest 2 KB text, empty stack: \(empty.text); full stack: \(full.text)")
        if !RunEnvironment.isCI {
            XCTAssertLessThan(full.median, empty.median * 1.5 + 5, "a full undo stack slowed the copy path")
        }
    }

    private func ingestTimes(_ count: Int, tag: String, into service: StorageService, container: ModelContainer)
        async throws
        -> PerfReport.Timing
    {
        var samples: [Double] = []
        for index in 0..<count {
            try await samples.append(milliseconds {
                _ = try await ingest(1, tag: "\(tag)\(index)", into: service, container: container)
            })
        }
        return PerfReport.timing(of: samples)
    }
}

/// What the stack keeps in memory at its limits (ADR 0008): sealed bytes only, never more than the budget.
@MainActor
final class UndoHistoryMemoryTests: XCTestCase {
    func test_whenFilledWithLargeClips_thenItHoldsNoMoreThanItsBudget() async throws {
        let container = try makeFileBackedContainer(for: self, seededWith: 0)
        let history = UndoHistory()
        let service = StorageService(modelContainer: container, environment: .testing { $0.undoHistory = history })
        let text = String(repeating: "a long line of text that is not compressed away. ", count: 18_000)
        let clipCount = 30
        for index in 0..<clipCount {
            let body = "\(index) \(text)"
            try await service.ingest(PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text", payload: Data(body.utf8), payloadString: body,
                timestamp: .now.addingTimeInterval(Double(index)), contentHash: "big-\(index)"
            ))
        }
        await service.waitForBackgroundWork()
        let stored = try ModelContext(container).fetch(
            FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp)])
        )
        let ids = stored.map(\.id)
        XCTAssertEqual(ids.count, clipCount)

        let before = PeakMemory.footprintBytes()
        for id in ids {
            try await service.deleteItems(ids: [id], reason: .user)
        }
        let after = PeakMemory.footprintBytes()
        let grownMB = Double(after - before) / 1_048_576
        let heldMB = Double(history.heldBytes) / 1_048_576
        PerfReport.emit(
            "undo memory: \(history.entryCount) entries holding " + String(format: "%.1f", heldMB) +
                " MB of a \(UndoPolicy.maxHeldBytes / 1_048_576) MB budget; footprint grew " +
                String(format: "%.1f", grownMB) + " MB"
        )

        XCTAssertLessThanOrEqual(history.heldBytes, UndoPolicy.maxHeldBytes)
        XCTAssertLessThanOrEqual(history.entryCount, UndoPolicy.maxEntries)
        XCTAssertGreaterThan(history.entryCount, 5, "large deletes were refused instead of held")
        if !RunEnvironment.isCI {
            let budgetMB = Double(UndoPolicy.maxHeldBytes / 1_048_576) + 24
            XCTAssertLessThan(grownMB, budgetMB, "the stack outgrew its budget")
        }

        history.clear()
        XCTAssertEqual(history.heldBytes, 0)
    }
}
