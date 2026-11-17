// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// Snapshot tests verifying the search filter bar fits cleanly at 14-inch display width (1512 pt)
/// in both Light and Dark appearances with zero clipping or wrapping.
/// Baselines live under __Snapshots__/FilterBarWidthSnapshotTests/.
@MainActor
final class FilterBarWidthSnapshotTests: XCTestCase {
    private static let fourteenInchWidth: CGFloat = 1512

    private func makeState() throws -> (AppState, ModelContainer) {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        for (app, bundleID, text) in [
            ("Safari", "com.apple.Safari", "https://copypesto.net"),
            ("Notes", "com.apple.Notes", "Meeting notes"),
            ("Terminal", "com.apple.Terminal", "swift test")
        ] {
            let item = ClipboardItem(
                type: .text,
                sourceBundleID: bundleID,
                sourceAppName: app,
                previewText: text,
                contentHash: UUID().uuidString,
                byteSize: text.utf8.count,
                deviceID: "test-device",
                sequenceNumber: 1
            )
            context.insert(item)
        }
        try context.save()
        let appState = AppState()
        appState.historyContainer = container
        appState.historyStore = HistoryStore(container: container)
        appState.isSearchActive = true
        return (appState, container)
    }

    private func snapshotFilterBar(
        colorScheme: ColorScheme,
        named name: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) throws {
        let (appState, container) = try makeState()
        let size = CGSize(width: Self.fourteenInchWidth, height: 92)
        let ground = colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.92)
        let root = CommandBarView()
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(ground)
            .environment(appState)
            .defaultAppStorage(AppDefaults.store)
            .modelContainer(container)
            .preferredColorScheme(colorScheme)
            .inBrandAccent()
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(
                of: controller,
                as: .image(size: size),
                named: name,
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    func test_when14InchDisplayWidthLight_thenFilterBarFitsWithoutClipping() throws {
        try snapshotFilterBar(colorScheme: .light, named: "light")
    }

    func test_when14InchDisplayWidthDark_thenFilterBarFitsWithoutClipping() throws {
        try snapshotFilterBar(colorScheme: .dark, named: "dark")
    }
}
