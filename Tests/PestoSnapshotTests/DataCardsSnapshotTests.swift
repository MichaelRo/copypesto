// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// The Backup and Sync cards of Settings → Data (ADR 0022), both off, as a grouped form. Baselines are OS-specific
/// (see `ClipboardCardTests`).
@MainActor
final class DataCardsSnapshotTests: XCTestCase {
    private func makeController() throws -> SyncController {
        let container = try ModelContainerSetup.makeInMemory()
        let secrets = SnapshotSecrets()
        var environment = SyncController.Environment(
            container: container, storage: StorageService(modelContainer: container),
            folder: URL(fileURLWithPath: "/Users/Shared/Pesto Snapshots/Pesto/Pesto Sync"),
            keyStore: ThisDeviceSyncKeyStore(secrets: secrets), deviceKeys: KeychainDeviceKeyStore(secrets: secrets),
            highWater: SealedHighWaterStore(url: FileManager.default.temporaryDirectory
                .appendingPathComponent("pesto-snap-hw")),
            defaults: AppDefaults.store, deviceID: "mac-a", deviceName: "Michael’s MacBook Air"
        )
        environment.timing.pollInterval = .seconds(3600)
        return SyncController(environment)
    }

    private func snapshot(
        withSync: Bool, size: CGSize, scheme: ColorScheme = .dark,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) throws {
        let appState = AppState()
        if withSync { appState.syncController = try makeController() }
        let container = try ModelContainerSetup.makeInMemory()
        let form = SwiftUI.Form { BackupSettings() }.formStyle(.grouped)
        let root = form
            .environment(appState)
            .defaultAppStorage(AppDefaults.store)
            .modelContainer(container)
            .frame(width: size.width, height: size.height)
            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
            .environment(\.colorScheme, scheme)
        let controller = NSHostingController(rootView: root.inBrandAccent())
        controller.view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(of: controller, as: .image(size: size), file: file, testName: testName, line: line)
        }
    }

    func test_bothOff_dark() throws {
        try snapshot(withSync: true, size: CGSize(width: 600, height: 560))
    }

    func test_bothOff_light() throws {
        try snapshot(withSync: true, size: CGSize(width: 600, height: 560), scheme: .light)
    }

    func test_bothOff_narrow() throws {
        try snapshot(withSync: true, size: CGSize(width: 440, height: 640))
    }

    func test_backupOnly_whenSyncIsUnavailable() throws {
        try snapshot(withSync: false, size: CGSize(width: 600, height: 380))
    }
}
