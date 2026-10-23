// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

private final class SpyBackend: LoginItemBackend, @unchecked Sendable {
    var status: LoginItemStatus
    var registerCalls = 0
    var unregisterCalls = 0
    var registerError: (any Error)?

    init(status: LoginItemStatus = .disabled) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        status = .disabled
    }
}

private struct BackendFailure: Error {}

@Suite("LoginItemService")
struct LoginItemServiceTests {
    @Test("enabling registers with the backend and reports enabled")
    func whenEnabled_thenRegisters() {
        let backend = SpyBackend()
        let service = LoginItemService(backend: backend)

        let status = service.setEnabled(true).status

        #expect(backend.registerCalls == 1)
        #expect(status == .enabled)
    }

    @Test("disabling unregisters")
    func whenDisabled_thenUnregisters() {
        let backend = SpyBackend(status: .enabled)
        let service = LoginItemService(backend: backend)

        let status = service.setEnabled(false).status

        #expect(backend.unregisterCalls == 1)
        #expect(status == .disabled)
    }

    @Test("enabling when already enabled does not register again")
    func whenAlreadyEnabled_thenNoRegister() {
        let backend = SpyBackend(status: .enabled)

        LoginItemService(backend: backend).setEnabled(true)

        #expect(backend.registerCalls == 0)
    }

    @Test("a failed register reports the real status, not the requested one")
    func whenRegisterFails_thenStatusIsBackendsTruth() {
        let backend = SpyBackend()
        backend.registerError = BackendFailure()

        let change = LoginItemService(backend: backend).setEnabled(true)

        #expect(change.status == .disabled)
    }

    @Test("requiresApproval is surfaced, and counts as not enabled for the toggle")
    func whenRequiresApproval_thenToggleOffButStatusVisible() {
        let service = LoginItemService(backend: SpyBackend(status: .requiresApproval))

        #expect(service.status == .requiresApproval)
        #expect(service.status.isOn == false)
    }

    @Test("a failed register hands the system's reason back so the toggle can show it")
    func whenRegisterFails_thenTheFailureIsReported() {
        let backend = SpyBackend()
        backend.registerError = BackendFailure()

        let change = LoginItemService(backend: backend).setEnabled(true)

        #expect(change.failure != nil)
    }

    @Test("a change that works reports no failure")
    func whenRegisterWorks_thenNoFailure() {
        #expect(LoginItemService(backend: SpyBackend()).setEnabled(true).failure == nil)
    }

    @Test("a copy macOS has not found yet is off and can be asked, not a dead switch")
    func whenTheSystemSaysNotFound_thenTheSwitchIsOffAndUsable() {
        #expect(LoginItemStatus(systemStatus: .notFound) == .disabled)
        #expect(LoginItemStatus(systemStatus: .notRegistered) == .disabled)
        #expect(LoginItemStatus(systemStatus: .enabled) == .enabled)
        #expect(LoginItemStatus(systemStatus: .requiresApproval) == .requiresApproval)
    }

    @Test("the stand-in backend refuses to register, so the real login items are never touched")
    func whenInert_thenRegisterThrows() {
        let backend = InertLoginItemBackend()

        #expect(backend.status == .disabled)
        #expect(throws: (any Error).self) { try backend.register() }
    }
}
