// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// Snapshot tests at the largest system text size (`.accessibilityExtraExtraExtraLarge`) across the shelf,
/// Settings panes, and Onboarding to catch overlapping or truncated labels.
/// Baselines live under __Snapshots__/LargeTextSizeSnapshotTests/.
@MainActor
final class LargeTextSizeSnapshotTests: XCTestCase {
    private static var baselineCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func makeState() throws -> (AppState, ModelContainer) {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        for (index, (app, text)) in [
            ("Notes", "Quarterly roadmap review and action items"),
            ("Safari", "https://copypesto.net/guide"),
            ("Xcode", "let snapshot = ClipboardCard(item: item)")
        ].enumerated() {
            let item = ClipboardItem(
                type: text.hasPrefix("https://") ? .url : .text,
                sourceAppName: app,
                previewText: text,
                contentHash: UUID().uuidString,
                byteSize: text.utf8.count,
                deviceID: "test-device",
                sequenceNumber: Int64(index + 1)
            )
            context.insert(item)
        }
        try context.save()
        let appState = AppState()
        appState.historyContainer = container
        appState.historyStore = HistoryStore(container: container)
        appState.hasAccessibilityPermission = true
        return (appState, container)
    }

    private func snapshotLargeText(
        _ view: some View,
        size: CGSize,
        appState: AppState,
        container: ModelContainer,
        named name: String? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let root = view
            .environment(appState)
            .defaultAppStorage(AppDefaults.store)
            .modelContainer(container)
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.calendar, Self.baselineCalendar)
            .preferredColorScheme(.dark)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.14))
            .inBrandAccent()
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: .darkAqua)
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

    func test_whenLargestTextSize_thenShelfFitsWithoutOverlap() throws {
        let (appState, container) = try makeState()
        snapshotLargeText(
            OverlayRootView().environment(\.shelfDrawsGlass, false),
            size: CGSize(width: 960, height: 260),
            appState: appState,
            container: container
        )
    }

    func test_whenLargestTextSize_thenSettingsPanesFitWithoutOverlap() throws {
        let (appState, container) = try makeState()
        let paneSize = CGSize(width: 680, height: 640)
        let panes: [(String, AnyView)] = [
            ("general", AnyView(GeneralPane())),
            ("appearance", AnyView(AppearanceSettings())),
            ("privacy", AnyView(PrivacyPane())),
            ("shortcuts", AnyView(ShortcutsPane())),
            ("collections", AnyView(CollectionsSettings())),
            ("snippets", AnyView(SnippetsSettings())),
            ("data", AnyView(DataPane(hasStorage: true)))
        ]
        for (name, pane) in panes {
            snapshotLargeText(
                pane,
                size: paneSize,
                appState: appState,
                container: container,
                named: name
            )
        }
    }

    func test_whenLargestTextSize_thenOnboardingFitsWithoutOverlap() throws {
        let (appState, container) = try makeState()
        snapshotLargeText(
            OnboardingView(appState: appState),
            size: OnboardingView.windowSize,
            appState: appState,
            container: container,
            named: "shelf"
        )
        snapshotLargeText(
            OnboardingView(appState: appState, shelfIntroduced: true),
            size: OnboardingView.windowSize,
            appState: appState,
            container: container,
            named: "pasting"
        )
        snapshotLargeText(
            OnboardingView(
                appState: appState,
                shelfIntroduced: true,
                pastingConfirmed: true,
                accessibilityGranted: true
            ),
            size: OnboardingView.windowSize,
            appState: appState,
            container: container,
            named: "lock"
        )
    }
}
