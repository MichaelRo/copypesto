// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Source app resolver")
struct SourceAppResolverTests {
    /// A filter chip showed the raw bundle ID ("com.apple.iChat") as its label —
    /// found by the `.sufficientElementDescription` audit, since a technical identifier reads as
    /// unlabelled to VoiceOver. Any bundle ID macOS can't resolve to an installed app (a defunct
    /// ID, or one whose app has since been uninstalled) hits this path, not just test fixtures.
    @Test("an unresolvable bundle ID gets a plain fallback name, not the raw identifier")
    @MainActor
    func whenBundleIDUnresolvable_thenPlainFallbackName() {
        let record = SourceAppResolver.computeRecord(bundleID: "com.apple.iChat")

        #expect(record.displayName == "Unknown app")
    }

    @Test("a known system daemon still gets its friendly override name")
    @MainActor
    func whenSystemDaemon_thenFriendlyName() {
        let record = SourceAppResolver.computeRecord(bundleID: "com.apple.SecurityAgent")

        #expect(record.displayName == "System Authentication")
    }
}
