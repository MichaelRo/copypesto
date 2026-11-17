// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import Pesto
@testable import PestoCore

private struct RefusingLoginItemBackend: LoginItemBackend {
    var status: LoginItemStatus {
        .disabled
    }

    func register() throws {
        throw LoginItemRefusal()
    }

    func unregister() throws {}
}

@Suite("LoginItemToggle")
@MainActor
struct LoginItemToggleTests {
    @Test("outside Applications explanation names Applications folder and includes macOS error")
    func whenOutsideApplications_thenExplanationMentionsApplicationsAndFailure() {
        let text = LoginItemToggle.explanation(
            for: "Operation not permitted",
            bundlePath: "/Users/test/Downloads/Pesto.app"
        )
        #expect(text.contains("Applications"))
        #expect(text.contains("macOS said: Operation not permitted"))
    }

    @Test("inside Applications explanation differs from outside Applications and includes macOS error")
    func whenInsideApplications_thenExplanationDiffers() {
        let inside = LoginItemToggle.explanation(
            for: "Service error",
            bundlePath: "/Applications/Pesto.app"
        )
        let outside = LoginItemToggle.explanation(
            for: "Service error",
            bundlePath: "/Users/test/Downloads/Pesto.app"
        )
        #expect(inside != outside)
        #expect(inside.contains("macOS said: Service error"))
    }

    @Test("injected LoginItemService returns refusal without touching system login items")
    func whenInjectedBackendRefuses_thenReturnsFailureWithoutSideEffects() {
        let service = LoginItemService(backend: RefusingLoginItemBackend())
        let change = service.setEnabled(true)
        #expect(change.status == .disabled)
        #expect(change.failure != nil)
        _ = LoginItemToggle(title: "Launch at login", service: service, bundlePath: "/Users/test/Downloads/Pesto.app")
    }
}
