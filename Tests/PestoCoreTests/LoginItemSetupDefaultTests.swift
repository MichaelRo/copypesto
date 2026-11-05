// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

private final class SpyBackend: LoginItemBackend, @unchecked Sendable {
    var status: LoginItemStatus
    var registerCalls = 0
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
        status = .disabled
    }
}

private struct Refused: Error {}

@Suite("Launch at login is on when setup ends, and the person's answer is kept")
struct LoginItemSetupDefaultTests {
    @Test("it is turned on once, for a person who has not been offered it and has it off")
    func whenOffAndNeverOffered_thenItIsTurnedOn() {
        #expect(LoginItemSetupDefault.shouldEnable(status: .disabled, alreadyOffered: false))
    }

    @Test("it is left alone when it is already on, waits for approval, is unavailable, or was offered before")
    func whenNotTheTime_thenLeftAlone() {
        #expect(!LoginItemSetupDefault.shouldEnable(status: .enabled, alreadyOffered: false))
        #expect(!LoginItemSetupDefault.shouldEnable(status: .requiresApproval, alreadyOffered: false))
        #expect(!LoginItemSetupDefault.shouldEnable(status: .unavailable, alreadyOffered: false))
        #expect(!LoginItemSetupDefault.shouldEnable(status: .disabled, alreadyOffered: true))
    }

    @Test("applying it registers the app and records that it was offered")
    func whenApplied_thenRegisteredAndRecorded() {
        let defaults = ThrowawayDefaults.make()
        let backend = SpyBackend()

        LoginItemSetupDefault.applyOnce(service: LoginItemService(backend: backend), defaults: defaults)

        #expect(backend.registerCalls == 1)
        #expect(defaults.value(for: Setting.loginItemOffered))
    }

    @Test("a person who turned it off is not turned on again by a second visit to the step")
    func whenTurnedOffAfterwards_thenItStaysOff() {
        let defaults = ThrowawayDefaults.make()
        let backend = SpyBackend()
        let service = LoginItemService(backend: backend)

        LoginItemSetupDefault.applyOnce(service: service, defaults: defaults)
        service.setEnabled(false)
        LoginItemSetupDefault.applyOnce(service: service, defaults: defaults)

        #expect(backend.registerCalls == 1)
        #expect(service.status == .disabled)
    }

    @Test("a refusal, such as an app outside Applications, is recorded too, so setup does not retry it")
    func whenRegistrationFails_thenItIsNotRetried() {
        let defaults = ThrowawayDefaults.make()
        let backend = SpyBackend()
        backend.registerError = Refused()

        LoginItemSetupDefault.applyOnce(service: LoginItemService(backend: backend), defaults: defaults)
        LoginItemSetupDefault.applyOnce(service: LoginItemService(backend: backend), defaults: defaults)

        #expect(backend.registerCalls == 1)
        #expect(defaults.value(for: Setting.loginItemOffered))
    }

    @Test("the record is this Mac's own state: named, defaulting to false and not carried by a backup")
    func theRecordIsPerMac() {
        #expect(Setting.loginItemOffered.name == "loginItemOffered")
        #expect(Setting.loginItemOffered.defaultValue == false)
        #expect(Setting.allNames.contains(Setting.loginItemOffered.name))
        #expect(!SettingsBackupManager.backupKeys.contains(Setting.loginItemOffered.name))
    }
}
