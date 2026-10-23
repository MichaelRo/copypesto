// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Storage notice on the shelf")
struct StorageNoticeTests {
    @Test("a history that is saved to disk shows no notice")
    func onDisk() {
        #expect(StorageNotice.message(hasStorage: true, isOnDisk: true) == nil)
    }

    @Test("a history held only in memory says that nothing of this session is kept")
    func inMemory() throws {
        let message = try #require(StorageNotice.message(hasStorage: true, isOnDisk: false))
        #expect(message.contains("not saved"))
        #expect(message.contains("lost when you quit"))
    }

    @Test("with no history at all the empty state speaks, not this notice")
    func noStorage() {
        #expect(StorageNotice.message(hasStorage: false, isOnDisk: false) == nil)
    }
}
