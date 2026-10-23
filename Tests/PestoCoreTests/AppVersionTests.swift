// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("AppVersion")
struct AppVersionTests {
    @Test("the version and the build are printed in one form")
    func whenInfoHasBoth_thenOneLine() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "45"]

        #expect(AppVersion.displayString(info: info) == "Version 1.2.3 (45)")
    }

    @Test("a missing value prints a dash, not an empty bracket")
    func whenInfoIsMissing_thenDashes() {
        #expect(AppVersion.displayString(info: [:]) == "Version \u{2013} (\u{2013})")
    }
}
