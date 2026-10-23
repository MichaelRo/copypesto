// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Development builds")
struct BuildKindTests {
    @Test("only the value make writes marks a development build")
    func whenInfoValue_thenOnlyYesIsDevelopment() {
        #expect(BuildKind.isDevelopment(infoValue: "YES"))
        #expect(!BuildKind.isDevelopment(infoValue: ""))
        #expect(!BuildKind.isDevelopment(infoValue: nil))
        #expect(!BuildKind.isDevelopment(infoValue: "NO"))
        #expect(!BuildKind.isDevelopment(infoValue: true))
    }

    @Test("a build with no marker, as the test host is, is not a development build")
    func whenNoMarker_thenNotDevelopment() {
        #expect(!BuildKind.isDevelopment)
    }
}
