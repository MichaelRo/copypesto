// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("SyncAvailability")
struct SyncAvailabilityTests {
    @Test("sync is available, and still off on every Mac until its person turns it on")
    func whenSyncAvailable_thenOffUntilTurnedOn() {
        #expect(SyncAvailability.isAvailable)
        #expect(Setting.syncEnabled.defaultValue == false)
    }
}
