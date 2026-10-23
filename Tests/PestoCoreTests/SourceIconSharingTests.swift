// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("An app's icon is drawn once, for ingest and for the cards")
struct SourceIconSharingTests {
    @Test("two resolvers and the card cache share one drawing of the same app")
    @MainActor
    func whenSameAppResolvedTwice_thenDrawnOnce() async {
        let icons = SourceIconCache()
        let first = SourceAppResolver(icons: icons)
        let second = SourceAppResolver(icons: icons)

        let a = await first.resolve(bundleID: "com.apple.finder")
        let b = await second.resolve(bundleID: "com.apple.finder")
        _ = icons.image(forBundleID: "com.apple.finder")

        #expect(a == b)
        #expect(icons.drawCount == 1)
    }

    @Test("a different app is a second drawing")
    @MainActor
    func whenTwoApps_thenTwoDrawings() async {
        let icons = SourceIconCache()
        let resolver = SourceAppResolver(icons: icons)

        _ = await resolver.resolve(bundleID: "com.apple.finder")
        _ = await resolver.resolve(bundleID: "com.apple.SecurityAgent")

        #expect(icons.drawCount == 2)
    }
}
