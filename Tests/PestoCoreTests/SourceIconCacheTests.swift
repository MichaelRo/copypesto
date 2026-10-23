// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

@MainActor
@Suite("Source app icon cache")
struct SourceIconCacheTests {
    @Test("a missing bundle ID has no icon")
    func whenNoBundleID_thenNil() {
        #expect(SourceIconCache().image(forBundleID: nil) == nil)
    }

    @Test("an installed app resolves to an icon")
    func whenInstalledApp_thenImage() {
        #expect(SourceIconCache().image(forBundleID: "com.apple.finder") != nil)
    }

    @Test("the same bundle ID is resolved once and shared by every card")
    func whenAskedTwice_thenSameInstance() throws {
        let cache = SourceIconCache()
        let first = try #require(cache.image(forBundleID: "com.apple.finder"))
        let second = try #require(cache.image(forBundleID: "com.apple.finder"))
        #expect(first === second)
    }
}
