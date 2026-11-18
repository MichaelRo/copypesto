// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Whether a build may share the widget's snapshot and key")
struct WidgetSharingTests {
    private let group = AppIdentity.appGroupID

    @Test("the app group and a team-prefixed widget Keychain group grant it, and name that group")
    func whenBothAreClaimed_thenTheGrantNamesTheKeychainGroup() {
        let grant = WidgetSharing.grant(
            appGroups: [group],
            keychainGroups: ["ABCDE12345.net.copypesto.pesto", "ABCDE12345.net.copypesto.pesto.widget"]
        )

        #expect(grant == WidgetSharing(keychainGroup: "ABCDE12345.net.copypesto.pesto.widget"))
    }

    @Test("a development build's entitlements, either one alone, or an unexpanded or empty prefix grant nothing")
    func whenAnythingIsMissing_thenThereIsNoGrant() {
        let widget = ["ABCDE12345.net.copypesto.pesto.widget"]
        #expect(WidgetSharing.grant(appGroups: nil, keychainGroups: nil) == nil)
        #expect(WidgetSharing.grant(appGroups: nil, keychainGroups: widget) == nil)
        #expect(WidgetSharing.grant(appGroups: [group], keychainGroups: nil) == nil)
        #expect(WidgetSharing.grant(appGroups: ["ABCDE12345.other"], keychainGroups: widget) == nil)
        #expect(WidgetSharing.grant(appGroups: [group], keychainGroups: ["ABCDE12345.net.copypesto.pesto"]) == nil)
        let unexpanded = "$(DEVELOPMENT_TEAM).net.copypesto.pesto.widget"
        #expect(WidgetSharing.grant(appGroups: [group], keychainGroups: [unexpanded]) == nil)
        #expect(WidgetSharing.grant(appGroups: [group], keychainGroups: [".net.copypesto.pesto.widget"]) == nil)
        #expect(WidgetSharing.grant(appGroups: [group], keychainGroups: ["AB-CD.net.copypesto.pesto.widget"]) == nil)
    }

    @Test("this test process is signed for no widget, so the Mac opens no group container")
    func whenTheTestRuns_thenItHasNoGrant() {
        #if os(macOS)
        #expect(WidgetSharing.current == nil)
        #expect(WidgetSharing.keychainGroup() == nil)
        #endif
    }
}
