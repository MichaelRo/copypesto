// SPDX-License-Identifier: MIT
import Testing
@testable import PestoMobile

@Suite("A request to join sync is shown over the library, not only on the Sync screen")
struct SyncApprovalPresentationTests {
    @Test("a pending request shows over the library when nothing else is presenting it")
    func whenPending_thenTheLibraryShowsIt() {
        #expect(SyncApprovalPresentation.presentsOverLibrary(
            hasPendingJoin: true, flowIsIdle: true, anotherSheetIsUp: false
        ))
    }

    @Test("no request, a set-up flow on screen, or another sheet up, shows nothing over the library")
    func whenAnythingElseIsPresenting_thenNotOverTheLibrary() {
        #expect(!SyncApprovalPresentation.presentsOverLibrary(
            hasPendingJoin: false, flowIsIdle: true, anotherSheetIsUp: false
        ))
        #expect(!SyncApprovalPresentation.presentsOverLibrary(
            hasPendingJoin: true, flowIsIdle: false, anotherSheetIsUp: false
        ))
        #expect(!SyncApprovalPresentation.presentsOverLibrary(
            hasPendingJoin: true, flowIsIdle: true, anotherSheetIsUp: true
        ))
    }
}
