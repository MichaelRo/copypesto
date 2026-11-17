// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftData
import Synchronization
import Testing
@testable import Pesto

extension HostedGlobals {
    @Suite("AppendIntegration", .serialized)
    @MainActor
    final class AppendIntegrationTests {
        @Test("double markCopy within window appends the second capture to the latest text clip via CapturePipeline")
        func whenDoubleCopyWithinWindow_thenCapturePipelineAppendsToLatest() async throws {
            let schema = Schema([ClipboardItem.self, ClipboardBlob.self, Pinboard.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])
            let storage = StorageService(modelContainer: container)

            let clock = Mutex(Date(timeIntervalSince1970: 2000))
            let coordinator = AppendModeCoordinator(window: 0.5, appendLifetime: 1.0) {
                clock.withLock { $0 }
            }
            let pipeline = CapturePipeline(
                storage: storage,
                appendMode: coordinator,
                didStore: {},
                didRefuse: { _ in }
            )

            let first = PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text",
                payload: Data("first line".utf8),
                payloadString: "first line",
                frontmostBundleID: "com.apple.Notes",
                timestamp: clock.withLock { $0 },
                contentHash: "hash-1"
            )
            _ = await coordinator.markCopy()
            await pipeline.handle(first)

            clock.withLock { $0 = $0.addingTimeInterval(0.2) }
            let triggered = await coordinator.markCopy()
            #expect(triggered)

            let second = PasteboardCapture(
                typeIdentifier: "public.utf8-plain-text",
                payload: Data("second line".utf8),
                payloadString: "second line",
                frontmostBundleID: "com.apple.Notes",
                timestamp: clock.withLock { $0 },
                contentHash: "hash-2"
            )
            await pipeline.handle(second)
            await storage.waitForBackgroundWork()

            let context = ModelContext(container)
            let items = try context.fetch(FetchDescriptor<ClipboardItem>())
            #expect(items.count == 1)
            let decrypted = items.first?.blob?.decryptedText()
            #expect(decrypted == "first line\nsecond line")
        }
    }
}
