// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Check for Updates")
struct UpdateCheckRouteTests {
    @Test("a development build explains itself instead of calling a Sparkle that was never started")
    func whenDevelopment_thenExplain() {
        #expect(UpdateCheckRoute.choose(isDevelopment: true) == .explainUnavailable)
    }

    @Test("a shipped build asks Sparkle")
    func whenShipped_thenSparkle() {
        #expect(UpdateCheckRoute.choose(isDevelopment: false) == .sparkle)
    }
}
