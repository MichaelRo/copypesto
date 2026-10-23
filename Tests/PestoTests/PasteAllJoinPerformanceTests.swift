// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import Pesto
@testable import PestoCore

extension HostedGlobals {
    /// P-07: Paste All decrypts the selected clips on the main thread, so the join stops at the size limit and counts
    /// what
    /// it left out without reading it. Fifty selected megabyte-sized clips must cost one limit's worth of work.
    @Suite("Joining many large clips for Paste All", .serialized)
    @MainActor
    struct PasteAllJoinPerformanceTests {
        @Test("fifty 1 MB clips join up to the limit, in a short time, without holding all of them")
        func join_fiftyLargeClips_stopsAtTheLimit() async throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-join-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let container = try ModelContainerSetup.openSynced(
                cloudKitEnabled: false, storeURL: directory.appendingPathComponent("clips.store")
            )
            let service = StorageService(modelContainer: container)
            for run in 0..<50 {
                let text = String(repeating: "A megabyte of text for Paste All. ", count: 30_000) + " \(run)"
                try await service.ingest(ClipKindFixtures.text(text))
            }
            let items = try container.mainContext.fetch(FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            ))
            try #require(items.count == 50)

            let before = PeakMemory.residentBytes()
            let started = ContinuousClock.now
            let joined = ClipJoin.join(items)
            let elapsed = ContinuousClock.now - started
            let growth = PeakMemory.residentBytes() - before

            let result = try #require(joined)
            #expect(result.text.utf8.count <= ClipSizePolicy.maxTextBytes)
            #expect(result.leftOut > 0, "the clips past the limit are left out, not read")
            #expect(elapsed < .seconds(RunEnvironment.isCI ? 10 : 3), "joining took \(elapsed)")
            #expect(growth < 200 * 1_048_576, "the join left \(growth / 1_048_576) MB more resident")
            PerfReport
                .emit("paste-all join of 50 x 1 MB: \(elapsed), +\(growth / 1_048_576) MB, left out \(result.leftOut)")
        }
    }
}
