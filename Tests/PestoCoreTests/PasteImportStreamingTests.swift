// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("Importing a big Paste library")
struct PasteImportStreamingTests {
    private let forever = RetentionPolicy(maxAge: .infinity, maxItemCount: 1_000_000, maxTotalBytes: .max)

    /// The process footprint is shared with every suite running beside this one, so it is only asserted off CI, and as
    /// the lowest of up to three passes (a neighbor's allocation only adds to a pass); the
    /// bytes a group holds are counted exactly and asserted everywhere.
    private var assertsFootprint: Bool {
        ProcessInfo.processInfo.environment["CI"] == nil
    }

    private func heldBytes(_ batch: PasteLibrarySnapshot.Batch) -> Int {
        batch.records.reduce(0) { $0 + $1.representations.reduce(0) { $0 + $1.dataBase64.utf8.count } }
    }

    private func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    @Test("a library over the cap imports its pinboards and the newest history, and every clip is accounted for")
    func whenOverTheCap_thenPinboardsAndNewestComeIn() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        for index in 1...3 {
            try fixture.addSnippet(
                id: index, list: 2, title: "Board \(index)", blob: PasteFixture.archive("pinned \(index)"), seconds: 10
            )
        }
        for index in 10...29 {
            try fixture.addSnippet(
                id: index, list: 1, title: nil, blob: PasteFixture.archive("history \(index)"),
                seconds: Double(index) * 100
            )
        }
        try fixture.addSnippet(id: 40, list: 1, title: nil, blob: nil)
        let container = try ModelContainerSetup.makeInMemory()
        let snapshot = try PasteLibrarySnapshot.open(databaseAt: fixture.url)
        let plan = try await snapshot.plan(cap: ImportCap(maxClips: 10, maxBytes: .max), retention: forever)
        let progress = LockedCounts()

        let summary = try await PasteMigrator(modelContainer: container).migrate(
            plan: plan, from: snapshot, includingHistory: true
        ) { done, total in progress.record(done, total) }

        #expect(plan.libraryClips == 24 && plan.unusable == 1)
        #expect(summary.imported == 10 && summary.skipped == 0)
        #expect(summary.imported + summary.skipped + plan.leftByLimits + plan.unusable == plan.libraryClips)
        let stored = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(stored.count == 10)
        #expect(stored.filter(\.isPinned).count == 3)
        let previews = Set(stored.filter { !$0.isPinned }.map(\.displayPreviewText))
        #expect(previews == Set((23...29).map { "history \($0)" }))
        #expect(progress.last == [10, 10])
    }

    @Test("an import run twice adds nothing the second time, and the snapshot's copy is removed after each")
    func whenImportedTwice_thenNoDuplicatesAndNoLeftovers() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        for index in 1...5 {
            try fixture.addSnippet(id: index, list: 1, title: nil, blob: PasteFixture.archive("clip \(index)"))
        }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-stream-scratch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let container = try ModelContainerSetup.makeInMemory()

        var imported: [Int] = []
        for _ in 0..<2 {
            let snapshot = try PasteLibrarySnapshot.open(databaseAt: fixture.url, temporaryDirectory: scratch)
            let plan = try await snapshot.plan(retention: forever)
            let summary = try await PasteMigrator(modelContainer: container).migrate(
                plan: plan, from: snapshot, includingHistory: true
            )
            imported.append(summary.imported)
        }

        #expect(imported == [5, 5])
        #expect(try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>()).count == 5)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
    }

    @Test("leaving the history out imports only the pinboards")
    func whenHistoryIsLeftOut_thenOnlyPinboardsComeIn() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        try fixture.addSnippet(id: 1, list: 2, title: nil, blob: PasteFixture.archive("pinned"))
        try fixture.addSnippet(id: 2, list: 1, title: nil, blob: PasteFixture.archive("history"))
        let container = try ModelContainerSetup.makeInMemory()
        let snapshot = try PasteLibrarySnapshot.open(databaseAt: fixture.url)
        let plan = try await snapshot.plan(retention: forever)

        let summary = try await PasteMigrator(modelContainer: container).migrate(
            plan: plan, from: snapshot, includingHistory: false
        )

        #expect(summary.imported == 1)
        #expect(plan.lead(includingHistory: false) == .pinboards)
    }

    @Test("clips are read in groups no bigger than the budget, and a clip over the budget is a group of its own")
    func whenBatched_thenNoGroupPassesTheBudget() {
        func entry(_ key: Int64, _ bytes: Int) -> PasteImportPlan.Entry {
            .init(snippetKey: key, dataKey: key, bytes: bytes, timestamp: .distantPast, pinboard: nil)
        }
        let sizes = [10, 10, 10, 50, 10, 10, 10, 10, 10]
        let plan = PasteImportPlan(
            pinboards: [], history: sizes.enumerated().map { entry(Int64($0.offset), $0.element) },
            libraryClips: sizes.count, unusable: 0, pinboardsLeftByCap: 0, historyLeftByCap: 0,
            historyLeftByRetention: 0, displacedExisting: 0
        )

        let groups = plan.batches(includingHistory: true, maxRecords: 4, maxBytes: 40)

        #expect(groups.map(\.count) == [3, 1, 4, 1])
        #expect(groups.flatMap { $0.map(\.snippetKey) } == Array(0..<9))
        #expect(groups.allSatisfy { $0.count <= 4 && ($0.count == 1 || $0.reduce(0) { $0 + $1.bytes } <= 40) })
    }

    @Test("a 400 MB library is read through with a small, flat memory peak")
    func whenLibraryIsLarge_thenMemoryStaysBounded() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        let text = String(repeating: "pesto genovese basil ", count: 10_000)
        let blob = try PasteFixture.archive(text)
        try fixture.addMany(from: 1, count: 2000, list: 1, blob: blob) { Double($0) }
        let snapshot = try PasteLibrarySnapshot.open(databaseAt: fixture.url)
        let plan = try await snapshot.plan(retention: forever)
        var peak = Int.max
        var read = 0
        var largestGroup = 0

        for _ in 0..<3 where peak >= 250_000_000 {
            let baseline = footprintBytes()
            var passPeak = 0
            read = 0
            for group in plan.batches(includingHistory: true) {
                let batch = try await snapshot.records(for: group[...])
                read += batch.records.count
                largestGroup = max(largestGroup, heldBytes(batch))
                passPeak = max(passPeak, footprintBytes() - baseline)
            }
            peak = min(peak, passPeak)
        }
        await snapshot.discard()

        #expect(read == 2000)
        #expect(blob.count * 2000 > 400_000_000)
        #expect(largestGroup <= 2 * PasteLibrarySnapshot.batchBytes, "a group held \(largestGroup / 1_048_576) MB")
        if assertsFootprint {
            #expect(peak < 250_000_000, "reading held \(peak / 1_048_576) MB; the library is 400 MB")
        }
    }

    @Test("a group of large clips is held at about its own size, not at several times it")
    func whenClipsAreLarge_thenAGroupStaysNearItsOwnSize() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        let blob = try PasteFixture.archive(String(repeating: "pesto genovese basil ", count: 250_000))
        try fixture.addMany(from: 1, count: 40, list: 1, blob: blob) { Double($0) }
        let snapshot = try PasteLibrarySnapshot.open(databaseAt: fixture.url)
        let plan = try await snapshot.plan(retention: forever)
        var largestGroup = 0
        var groups = 0

        for group in plan.batches(includingHistory: true) {
            let batch = try await snapshot.records(for: group[...])
            largestGroup = max(largestGroup, heldBytes(batch))
            groups += 1
        }
        await snapshot.discard()

        // The process footprint of such a group was measured once at 1.4 times the group (ADR 0032); it is not
        // asserted here because every suite running beside this one moves it.
        #expect(largestGroup <= 2 * PasteLibrarySnapshot.batchBytes)
        #expect(groups > 10, "40 clips of 5 MB should not be one group")
    }

    @Test("importing 2,000 ordinary clips through ingest in groups finishes and keeps every one")
    func whenImportingManyOrdinaryClips_thenAllAreKept() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        let filler = String(repeating: "pesto genovese basil ", count: 15)
        try fixture.run("BEGIN;")
        for id in 1...2000 {
            try fixture.addSnippet(
                id: id, list: 1, title: nil, blob: PasteFixture.archive("clip \(id) " + filler), seconds: Double(id)
            )
        }
        try fixture.run("COMMIT;")
        let container = try ModelContainerSetup.makeInMemory()
        let snapshot = try PasteLibrarySnapshot.open(databaseAt: fixture.url)
        let plan = try await snapshot.plan(retention: forever)

        let summary = try await PasteMigrator(modelContainer: container).migrate(
            plan: plan, from: snapshot, includingHistory: true
        )
        #expect(summary.imported == 2000 && summary.skipped == 0)
    }

    @Test("an import that fails part way keeps what came in, can be undone, and says how many")
    func whenTheReadFailsPartWay_thenWhatCameInIsUndoableAndCounted() async throws {
        let fixture = try PasteFixture()
        defer { fixture.close() }
        let total = PasteLibrarySnapshot.batchRecords + 6
        try fixture.run("BEGIN;")
        for index in 1...total {
            try fixture.addSnippet(id: index, list: 1, title: nil, blob: PasteFixture.archive("clip \(index)"))
        }
        try fixture.run("COMMIT;")
        let container = try ModelContainerSetup.makeInMemory()
        let history = UndoHistory()
        let snapshot = try PasteLibrarySnapshot.open(databaseAt: fixture.url)
        let plan = try await snapshot.plan(retention: forever)

        do {
            _ = try await PasteMigrator(modelContainer: container).migrate(
                plan: plan, from: snapshot, includingHistory: true, undoHistory: history
            ) { done, _ in
                if done == PasteLibrarySnapshot.batchRecords { await snapshot.discard() }
            }
            Issue.record("the second group should not be readable")
        } catch let interrupted as PasteMigrator.Interrupted {
            #expect(interrupted.summary.imported == PasteLibrarySnapshot.batchRecords)
            #expect(interrupted.cause is PasteLibraryReader.ReadError)
        }
        let stored = try ModelContext(container).fetch(FetchDescriptor<ClipboardItem>())
        #expect(stored.count == PasteLibrarySnapshot.batchRecords)
        #expect(history.entryCount == 1, "the clips that came in are one Undo")
    }
}

final class LockedCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[Int]] = []

    func record(_ done: Int, _ total: Int) {
        lock.lock()
        values.append([done, total])
        lock.unlock()
    }

    var last: [Int]? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }
}
