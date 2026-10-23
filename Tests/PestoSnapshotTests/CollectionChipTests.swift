// SPDX-License-Identifier: MIT
import AppKit
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Pesto

/// Snapshot tests for `CollectionChip` — covers the chip strip variants used
/// in the overlay's command bar, including the inline "+" chip introduced in
/// 13cf06d. Baselines under __Snapshots__/CollectionChipTests/.
@MainActor
final class CollectionChipTests: XCTestCase {
    private func snapshotChip(
        _ chip: some View,
        size: CGSize = CGSize(width: 160, height: 36),
        named name: String? = nil,
        colorScheme: ColorScheme = .dark,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let root = chip
            .preferredColorScheme(colorScheme)
            .padding(8)
            .frame(width: size.width, height: size.height)
        let controller = NSHostingController(rootView: root)
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

    func test_unselectedChip_systemSymbol() {
        snapshotChip(
            CollectionChip(name: "Snippets", symbolName: "doc.text", color: .blue, isSelected: false)
        )
    }

    func test_selectedChip_revealsName() {
        snapshotChip(
            CollectionChip(name: "Snippets", symbolName: "doc.text", color: .blue, isSelected: true)
        )
    }

    func test_emojiChip() {
        snapshotChip(
            CollectionChip(name: "Quotes", symbolName: "💬", color: .orange, isSelected: false)
        )
    }

    /// Regression guard for the inline "+" chip in CommandBarView (13cf06d).
    func test_inlineAddChip() {
        snapshotChip(
            CollectionChip(name: "New", symbolName: "plus", color: .secondary, isSelected: false)
        )
    }

    func test_unselectedChip_lightMode() {
        snapshotChip(
            CollectionChip(name: "Snippets", symbolName: "doc.text", color: .blue, isSelected: false),
            named: "light",
            colorScheme: .light
        )
    }
}
