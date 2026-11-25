// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Leaving sync on an iPhone")
@MainActor
struct MobileSyncLeaveTests {
    @Test("Leave Sync empties what sync brought besides the history: the app catalog")
    func whenLeaving_thenTheAppCatalogIsEmptied() {
        let defaults = ThrowawayDefaults.make()
        var left = 0
        let sync = MobileSync(MobileSync.Environment(
            folder: BookmarkedSyncFolder(defaults: defaults, bookmarks: FakeBookmarks()), deviceKind: .iPhone,
            defaults: defaults, authenticator: StubUserAuthenticator(available: true, grants: true),
            grace: AuthenticationGrace(), makeController: { _ in nil }, didLeave: { left += 1 }
        ))
        sync.leave()
        #expect(left == 1)
    }
}
