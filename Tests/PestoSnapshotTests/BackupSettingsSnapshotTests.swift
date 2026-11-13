// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Pesto

/// The backup summary at the top of Settings → Data and the restore sheet while it works. Baselines are OS-specific
/// (see `ClipboardCardTests`).
@MainActor
final class BackupSettingsSnapshotTests: XCTestCase {
    /// Dates are drawn in the locale and zone the baselines were recorded in, so they hold on any Mac and in any
    /// season.
    private static var baselineCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private let savedAt = Date(timeIntervalSince1970: 1_793_801_100)

    private func snapshot(
        _ view: some View, size: CGSize, file: StaticString = #filePath, testName: String = #function,
        line: UInt = #line
    ) {
        let root = view
            .environment(AppState())
            .defaultAppStorage(AppDefaults.store)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.16))
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.calendar, Self.baselineCalendar)
        let controller = NSHostingController(rootView: root.inBrandAccent())
        controller.view.appearance = NSAppearance(named: .darkAqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(of: controller, as: .image(size: size), file: file, testName: testName, line: line)
        }
    }

    private func summary(sync: SyncStatus? = nil) -> some View {
        BackupSummaryRow(chip: .upToDate(savedAt), now: savedAt, sync: sync).padding(.horizontal, 20)
    }

    func test_summary_wide() {
        snapshot(summary(), size: CGSize(width: 600, height: 60))
    }

    func test_summary_narrow() {
        snapshot(summary(), size: CGSize(width: 440, height: 90))
    }

    func test_summary_withSync_narrow() {
        snapshot(summary(sync: .upToDate(savedAt)), size: CGSize(width: 520, height: 90))
    }

    func test_summary_withSync_veryNarrow() {
        snapshot(summary(sync: .upToDate(savedAt)), size: CGSize(width: 360, height: 120))
    }

    func test_restoreWorking() {
        snapshot(
            VStack(alignment: .leading, spacing: 14) {
                Text("Restore from Backup").font(.title3.weight(.semibold))
                SheetWorkingIndicator()
            }
            .padding(20),
            size: CGSize(width: 440, height: 240)
        )
    }
}
