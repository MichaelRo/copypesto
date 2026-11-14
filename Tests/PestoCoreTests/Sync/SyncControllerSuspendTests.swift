// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Sync controller on a device that goes to the background", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct SyncControllerSuspendTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-suspend-\(UUID().uuidString)")
    let time = TimeBox()

    @Test("suspending stops the exchanges but leaves sync on, and resuming picks up what arrived meanwhile")
    func whenSuspendedAndResumed_thenSyncStaysOnAndCatchesUp() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let mac = try SyncMac(name: "mac-a", folder: folder, time: time)
        await mac.controller.turnOn()
        guard case let .recoveryKey(key) = mac.controller.flow else {
            Issue.record("expected the recovery key, got \(mac.controller.flow)")
            return
        }
        let phone = try SyncMac(name: "iphone-b", folder: folder, time: time, deviceKind: .iPhone)
        await phone.controller.turnOn()
        await phone.controller.useRecoveryKey(key)
        phone.controller.confirmJoin()
        time.advance()
        await phone.controller.syncNow()

        phone.controller.suspend()
        #expect(phone.controller.isEnabled)
        #expect(phone.defaults.value(for: Setting.syncEnabled))
        try await mac.site.copy("while the phone was away")
        time.advance()
        await mac.controller.syncNow()
        await phone.controller.syncNow()
        #expect(try phone.clips().isEmpty, "a suspended device reads nothing")

        phone.controller.resumeIfEnabled()
        time.advance()
        await phone.controller.syncNow()
        #expect(try phone.clips() == ["while the phone was away"])
        if case .upToDate = phone.controller.status {} else { Issue.record("status \(phone.controller.status)") }
    }

    @Test("an iPhone's controller speaks as an iPhone when no other device has announced itself")
    func whenTheDeviceIsAnIPhone_thenItsMessagesNameIt() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let mac = try SyncMac(name: "mac-a", folder: folder, time: time)
        await mac.controller.turnOn()
        let phone = try SyncMac(name: "iphone-b", folder: folder, time: time, deviceKind: .iPhone)
        #expect(phone.controller.deviceKind == .iPhone)
        await phone.controller.turnOn()
        #expect(phone.controller.flow == .needsKey)
        try FileManager.default.removeItem(at: SyncFolderLayout(root: folder).device("mac-a"))

        phone.controller.askAnotherMac()

        #expect(phone.controller.flow == .failed(SyncCopy.noOtherDevice(.iPhone)))
    }
}
