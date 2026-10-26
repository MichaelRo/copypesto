// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("StorageService wipe suggestion ledger")
struct StorageServiceWipeSuggestionTests {
    private final class WipeTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var calls: Int {
            lock.withLock { count }
        }

        func record() {
            lock.withLock { count += 1 }
        }
    }

    @Test("clearNonPinned in range all invokes wipeSuggestionLedger")
    func clearNonPinnedAll_invokesWipeSuggestionLedger() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let tracker = WipeTracker()
        let service = StorageService(modelContainer: container, environment: .testing {
            $0.wipeSuggestionLedger = { tracker.record() }
        })
        _ = try await service.clearNonPinned(in: .all)
        #expect(tracker.calls == 1)
    }

    @Test("clearNonPinned in non-all range does not invoke wipeSuggestionLedger")
    func clearNonPinnedRecent_doesNotInvokeWipeSuggestionLedger() async throws {
        let container = try ModelContainerSetup.makeInMemory().synced
        let tracker = WipeTracker()
        let service = StorageService(modelContainer: container, environment: .testing {
            $0.wipeSuggestionLedger = { tracker.record() }
        })
        _ = try await service.clearNonPinned(in: .lastHour)
        #expect(tracker.calls == 0)
    }
}
