// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Clear on Quit policy")
struct ClearOnQuitPolicyTests {
    @Test("when the setting is on and the history is readable, quitting clears it")
    func whenEnabledAndReadable_thenClears() {
        #expect(ClearOnQuitPolicy.shouldClear(enabled: true, hasStorage: true, keyUnresolved: false))
    }

    @Test("when the key is missing, quitting must not clear the history the person was told to keep")
    func whenKeyUnresolved_thenNeverClears() {
        #expect(!ClearOnQuitPolicy.shouldClear(enabled: true, hasStorage: true, keyUnresolved: true))
    }

    @Test("when the setting is off or there is no storage, nothing is cleared")
    func whenDisabledOrNoStorage_thenNeverClears() {
        #expect(!ClearOnQuitPolicy.shouldClear(enabled: false, hasStorage: true, keyUnresolved: false))
        #expect(!ClearOnQuitPolicy.shouldClear(enabled: true, hasStorage: false, keyUnresolved: false))
    }
}
