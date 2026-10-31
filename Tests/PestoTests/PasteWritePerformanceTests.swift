// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Testing
@testable import Pesto

extension HostedGlobals {
    /// What the paste costs before any app is involved: `AppState.writeItem` opening the clip and putting it on the
    /// board, per kind of clip. The wait for the target app and the keystroke are in `scripts/bench-latency.sh`.
    @Suite("Writing a clip to the pasteboard, per kind", .serialized)
    @MainActor
    struct PasteWritePerformanceTests {
        @Test("each kind of clip is written to the pasteboard within its budget")
        func writeItem_perKind() async throws {
            let container = try ModelContainerSetup.makeInMemory()
            let service = StorageService(modelContainer: container)
            let state = AppState()
            let context = ModelContext(container)

            for fixture in ClipKindFixtures.all() {
                let known = try Set(context.fetch(FetchDescriptor<ClipboardItem>()).map(\.id))
                try await service.ingest(fixture.capture)
                let item = try #require(try context.fetch(FetchDescriptor<ClipboardItem>())
                    .first { !known.contains($0.id) })
                #expect(item.type == fixture.storedType, "\(fixture.name) was stored as \(item.type)")
                let result = PerfReport.time { _ = state.writeItem(item) }
                PerfReport.emit("paste-write \(fixture.name) (\(item.byteSize) bytes): \(result.text)")
                if !RunEnvironment.isCI {
                    let budget = fixture.name.hasPrefix("large") || fixture.name.hasPrefix("picture") ? 20.0 : 5.0
                    #expect(
                        result.median < budget,
                        "\(fixture.name) took \(result.median) ms to write; budget \(budget) ms"
                    )
                }
            }
        }
    }
}
