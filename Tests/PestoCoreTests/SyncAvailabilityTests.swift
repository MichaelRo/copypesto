// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("SyncAvailability")
struct SyncAvailabilityTests {
    @Test("sync stays off in v1, whatever an old preference says")
    func whenSyncUnavailable_thenOff() {
        #expect(SyncAvailability.isAvailable == false)
    }
}
