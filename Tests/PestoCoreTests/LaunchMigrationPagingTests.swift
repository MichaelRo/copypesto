// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import PestoCore

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func add(_ entry: String) {
        lock.withLock { entries.append(entry) }
    }

    var all: [String] {
        lock.withLock { entries }
    }
}

private final class ArrivalGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false

    func open() {
        lock.withLock { isOpen = true }
    }

    func waitUntilOpen(timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !lock.withLock({ isOpen }), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }
}

private struct LoggingLastItemStore: LastItemStoring {
    let log: EventLog
    func write(id _: UUID, preview _: String, type _: String, timestamp _: Date, sourceApp _: String?) {
        log.add("ingest")
    }

    func clear() {}
    func clear(ifItemID _: UUID) {}
}

@Suite("A pass over the whole history lets an ingest through between pages")
struct LaunchMigrationPagingTests {
    private func capture(_ text: String, at seconds: Double) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text", payload: Data(text.utf8), payloadString: text,
            timestamp: Date(timeIntervalSince1970: seconds),
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    @Test("a copy made during a migration is stored before the migration ends, and every clip is still visited")
    func whenACopyArrivesMidPass_thenItIsNotHeldUntilTheEnd() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let log = EventLog()
        let service = StorageService(
            modelContainer: container, environment: .testing { $0.lastItemStore = LoggingLastItemStore(log: log) }
        )
        for number in 0..<200 {
            try await service.ingest(capture("clip number \(number)", at: 1000 + Double(number)))
        }
        let before = log.all.count

        let gate = ArrivalGate()
        let arrival = Task {
            gate.open()
            try await service.ingest(capture("a copy during the pass", at: 5000))
        }
        var waited = false
        try await service.forEachClip(pageSize: 2) { _ in
            // Task.yield lets through only what is already queued on the actor, so the pass must not start its
            // pages until the copy has started; otherwise a busy machine runs the whole pass first.
            // Pages of two give it a hundred yield points: a loaded machine can delay the copy by milliseconds, and a
            // pass of four pages finished before it arrived.
            if !waited {
                waited = true
                gate.waitUntilOpen()
            }
            log.add("visit")
        }
        try await arrival.value

        let events = Array(log.all.dropFirst(before))
        let visits = events.count(where: { $0 == "visit" })
        #expect(visits >= 200, "every clip should be visited")
        let ingestAt = try #require(events.firstIndex(of: "ingest"), "the copy was never stored")
        let lastVisitAt = try #require(events.lastIndex(of: "visit"))
        #expect(ingestAt < lastVisitAt, "the copy waited for the whole pass")
    }

    @Test("a page is saved before the next one starts, so an interrupted pass keeps what it finished")
    func whenThePassIsInterrupted_thenEarlierPagesAreKept() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let service = StorageService(
            modelContainer: container,
            environment: .testing { $0.lastItemStore = LoggingLastItemStore(log: EventLog()) }
        )
        for number in 0..<120 {
            try await service.ingest(capture("clip \(number)", at: 1000 + Double(number)))
        }
        struct Interrupted: Error {}

        var visited = 0
        await #expect(throws: Interrupted.self) {
            try await service.forEachClip(pageSize: 50) { item in
                item.isPinned = true
                visited += 1
                if visited == 75 { throw Interrupted() }
            }
        }

        let pinned = try ModelContext(container)
            .fetchCount(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.isPinned }))
        #expect(pinned == 50, "the first page was saved, and the interrupted second page was rolled back")
        try await service.ingest(capture("an unrelated copy", at: 9000))
        let afterNextSave = try ModelContext(container)
            .fetchCount(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.isPinned }))
        #expect(afterNextSave == 50, "the next save committed the interrupted page")
    }
}
