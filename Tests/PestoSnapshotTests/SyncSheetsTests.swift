// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// The sync sheets and the Sync rows (ADR 0018, the board "Sync: set up, join, pair, states, reset"). Baselines are
/// OS-specific (see `ClipboardCardTests`).
@MainActor
final class SyncSheetsTests: XCTestCase {
    private func makeController(folder: URL? = nil) throws -> SyncController {
        let container = try ModelContainerSetup.makeInMemory().synced
        // A fixed path, so the folder name in the pictures does not change from run to run; nothing is written there.
        let root = folder ?? URL(fileURLWithPath: "/Users/Shared/Pesto Snapshots/Pesto/Pesto Sync")
        let secrets = SnapshotSecrets()
        var environment = SyncController.Environment(
            container: container, storage: StorageService(modelContainer: container), folder: root,
            keyStore: ThisDeviceSyncKeyStore(secrets: secrets), deviceKeys: KeychainDeviceKeyStore(secrets: secrets),
            highWater: SealedHighWaterStore(url: FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-snap-hw")),
            defaults: AppDefaults.store, deviceID: "mac-a", deviceName: "Michael’s MacBook Air"
        )
        environment.timing.pollInterval = .seconds(3600)
        return SyncController(environment)
    }

    private func snapshot(
        _ view: some View, size: CGSize = CGSize(width: 520, height: 420), scheme: ColorScheme = .dark,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        let root = view
            .environment(AppState())
            .defaultAppStorage(AppDefaults.store)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
            .environment(\.colorScheme, scheme)
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(of: controller, as: .image(size: size), file: file, testName: testName, line: line)
        }
    }

    func test_setUp() throws {
        try snapshot(SyncSetUpSheet(controller: makeController()), size: CGSize(width: 520, height: 470))
    }

    func test_setUp_light() throws {
        try snapshot(
            SyncSetUpSheet(controller: makeController()),
            size: CGSize(width: 520, height: 470),
            scheme: .light
        )
    }

    func test_join() throws {
        try snapshot(SyncJoinSheet(controller: makeController(), thisMac: 1204, group: 3871))
    }

    func test_keychainOff() throws {
        try snapshot(SyncKeychainOffSheet(controller: makeController()), size: CGSize(width: 520, height: 300))
    }

    func test_needsKey() throws {
        try snapshot(SyncNeedsKeySheet(controller: makeController()), size: CGSize(width: 520, height: 400))
    }

    func test_enterKey() throws {
        try snapshot(SyncEnterKeySheet(controller: makeController()), size: CGSize(width: 520, height: 230))
    }

    func test_pairing() throws {
        let words = ["amber", "fern", "marble", "river", "quilt", "lantern"]
        try snapshot(
            SyncPairingSheet(controller: makeController(), words: words, approver: "Michael’s Mac mini"),
            size: CGSize(width: 520, height: 280)
        )
    }

    func test_approve() throws {
        let me = SyncDeviceKeys.generate()
        let request = try SyncJoinRequest(
            deviceID: "mac-b", name: "Michael’s MacBook Air", keys: me.publicKeys, vaultID: Data(count: 16),
            createdAt: .now
        ).signed(by: me)
        let words = ["amber", "fern", "marble", "river", "quilt", "lantern"]
        try snapshot(
            SyncApproveSheet(
                controller: makeController(),
                pending: SyncPendingJoin(request: request, words: words)
            ),
            size: CGSize(width: 520, height: 280)
        )
    }

    func test_recoveryKey() throws {
        try snapshot(
            SyncRecoveryKeySheet(controller: makeController(), key: "K7QH-2MXA-9PDW-RT4N-8CVB-3LYE-6ZUJ-5GFS-AB2C"),
            size: CGSize(width: 520, height: 340)
        )
    }

    func test_failed() throws {
        try snapshot(
            SyncFailedSheet(
                controller: makeController(),
                message: "That recovery key does not open the sync in this folder."
            ),
            size: CGSize(width: 520, height: 200)
        )
    }
}

final class SnapshotSecrets: SecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? {
        lock.withLock { items["\(service)|\(account)"] }
    }

    func write(_ data: Data, service: String, account: String) throws {
        lock.withLock { items["\(service)|\(account)"] = data }
    }

    func delete(service: String, account: String) {
        lock.withLock { _ = items.removeValue(forKey: "\(service)|\(account)") }
    }
}
