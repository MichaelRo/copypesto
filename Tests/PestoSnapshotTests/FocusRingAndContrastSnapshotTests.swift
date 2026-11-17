// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// Snapshot tests for keyboard focus rings (cards and filter/collection chips with bottom clearance)
/// and high-contrast + reduced-transparency rendering of `ShelfBackground`, `ClipboardCard`, and
/// `ToastView` across all 4 `AppTheme`s in Light and Dark appearances.
/// Baselines live under __Snapshots__/FocusRingAndContrastSnapshotTests/.
@MainActor
final class FocusRingAndContrastSnapshotTests: XCTestCase {
    private func makeItem() throws -> ClipboardItem {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let item = ClipboardItem(
            type: .text,
            sourceAppName: "Notes",
            previewText: "Keyboard focus ring and high-contrast surface check",
            contentHash: UUID().uuidString,
            byteSize: 52,
            deviceID: "test-device",
            sequenceNumber: 1
        )
        context.insert(item)
        return item
    }

    private func withTheme(_ theme: AppTheme, _ body: () throws -> Void) rethrows {
        let previousLight = AppDefaults.store.value(for: Setting.appTheme)
        let previousDark = AppDefaults.store.value(for: Setting.appThemeDark)
        AppDefaults.store.set(theme.rawValue, for: Setting.appTheme)
        AppDefaults.store.set("", for: Setting.appThemeDark)
        defer {
            AppDefaults.store.set(previousLight, for: Setting.appTheme)
            AppDefaults.store.set(previousDark, for: Setting.appThemeDark)
        }
        try body()
    }

    // MARK: - Focus rings and bottom clearance

    func test_whenCardFocused_thenFocusRingHasBottomClearance() throws {
        let item = try makeItem()
        let size = CGSize(width: 240, height: 220)
        for dark in [false, true] {
            let ground = Color(hex: AppTheme.basil.groundHex(dark: dark)) ?? .black
            let root = ClipboardCard(item: item, isFocused: true, shortcutNumber: 1)
                .defaultAppStorage(AppDefaults.store)
                .environment(\.shelfDrawsGlass, false)
                .preferredColorScheme(dark ? .dark : .light)
                .frame(width: 200, height: 180)
                .padding(20)
                .background(ground)
                .inBrandAccent()
            let controller = NSHostingController(rootView: root)
            controller.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            withSnapshotTesting(record: .missing) {
                assertSnapshot(
                    of: controller,
                    as: .image(size: size),
                    named: dark ? "dark" : "light"
                )
            }
        }
    }

    func test_whenFilterAndCollectionChipsFocused_thenRingHasBottomClearance() {
        let size = CGSize(width: 320, height: 48)
        for dark in [false, true] {
            let ground = Color(hex: AppTheme.basil.groundHex(dark: dark)) ?? .black
            let root = HStack(spacing: 10) {
                PestoChip(label: "Links", icon: "link", isActive: false, hasKeyboardCursor: true) {}
                PestoChip(label: "Today", isActive: true, hasKeyboardCursor: true) {}
                CollectionChip(name: "Snippets", symbolName: "doc.text", color: .blue, isSelected: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: size.width, height: size.height)
            .background(ground)
            .defaultAppStorage(AppDefaults.store)
            .preferredColorScheme(dark ? .dark : .light)
            .inBrandAccent()
            let controller = NSHostingController(rootView: root)
            controller.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            withSnapshotTesting(record: .missing) {
                assertSnapshot(
                    of: controller,
                    as: .image(size: size),
                    named: dark ? "dark" : "light"
                )
            }
        }
    }

    // MARK: - Increased contrast + Reduce Transparency across all 4 AppThemes

    func test_whenIncreasedContrastAndReducedTransparency_thenShelfBackgroundAndCardRenderCleanly() throws {
        let item = try makeItem()
        let size = CGSize(width: 260, height: 240)
        for theme in AppTheme.allCases {
            withTheme(theme) {
                for dark in [false, true] {
                    let accent = Color.pestoAccent(stored: AccentChoice.defaultStored, theme: theme.rawValue)
                    let root = ZStack {
                        ShelfBackground()
                        ClipboardCard(item: item, isFocused: true, shortcutNumber: 1)
                            .frame(width: 200, height: 180)
                    }
                    .frame(width: size.width, height: size.height)
                    .defaultAppStorage(AppDefaults.store)
                    .shelfSurfaceEnvironment()
                    .environment(\.pestoAccent, accent)
                    .environment(\.reduceTransparencyOverride, true)
                    .preferredColorScheme(dark ? .dark : .light)
                    let controller = NSHostingController(rootView: root)
                    controller.view.appearance = NSAppearance(
                        named: dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
                    )
                    withSnapshotTesting(record: .missing) {
                        assertSnapshot(
                            of: controller,
                            as: .image(size: size),
                            named: "\(theme.rawValue)-\(dark ? "dark" : "light")"
                        )
                    }
                }
            }
        }
    }

    func test_whenIncreasedContrastAndReducedTransparency_thenToastViewRendersCleanly() throws {
        for theme in AppTheme.allCases {
            try withTheme(theme) {
                for dark in [false, true] {
                    let toastController = ToastWindowController()
                    toastController.show(.upToDate, holds: true)
                    let panel = try XCTUnwrap(
                        NSApp.windows.last { $0.accessibilityLabel() == "Pesto notice" }
                    )
                    defer { panel.orderOut(nil) }
                    panel.appearance = NSAppearance(
                        named: dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
                    )
                    let contentView = try XCTUnwrap(panel.contentView)
                    contentView.appearance = panel.appearance
                    withSnapshotTesting(record: .missing) {
                        assertSnapshot(
                            of: contentView,
                            as: .image(size: contentView.bounds.size),
                            named: "\(theme.rawValue)-\(dark ? "dark" : "light")"
                        )
                    }
                }
            }
        }
    }
}
