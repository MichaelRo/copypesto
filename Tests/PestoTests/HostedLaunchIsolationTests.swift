// SPDX-License-Identifier: MIT
import Testing
@testable import Pesto

extension HostedGlobals {
    /// Regression: the XCTest host is the real Pesto.app, so an unguarded
    /// launch opened the user's real clips.store, swept retention on it, and started the
    /// pasteboard watcher. Only bootStorage() and a test that restores what it sets may write ScriptingContext.
    @Suite("Hosted test launch isolation")
    @MainActor
    struct HostedLaunchIsolationTests {
        @Test("the test host never boots storage")
        func whenRunningAsTestHost_thenStorageIsNotBooted() {
            #expect(ScriptingContext.modelContainer == nil)
            #expect(ScriptingContext.appState == nil)
        }
    }
}
