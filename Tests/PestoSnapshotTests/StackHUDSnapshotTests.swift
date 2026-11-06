// SPDX-License-Identifier: MIT
import AppKit
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Pesto

/// The Paste One by One HUD has no picture in the docs and XCUITest cannot capture its panel, so its view is drawn
/// here, in each appearance and at the end of a stack. Baselines are OS-specific (see `ClipboardCardTests`).
@MainActor
final class StackHUDSnapshotTests: XCTestCase {
    private func snapshot(
        progress: String, preview: String, dark: Bool,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        let model = StackHUDViewModel()
        model.progress = progress
        model.preview = preview
        model.hint = "⌘V"
        let root = StackHUDView(model: model)
            .padding(24)
            .background(dark ? Color(white: 0.13) : Color(red: 0.92, green: 0.85, blue: 0.71))
            .preferredColorScheme(dark ? .dark : .light)
            .inBrandAccent()
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(
                of: controller, as: .image(size: CGSize(width: 388, height: 100)),
                file: file, testName: testName, line: line
            )
        }
    }

    func test_pastingTheSecondOfThree_light() {
        snapshot(progress: "2/3", preview: "Order 4417 ships Tuesday, signature needed", dark: false)
    }

    func test_pastingTheSecondOfThree_dark() {
        snapshot(progress: "2/3", preview: "Order 4417 ships Tuesday, signature needed", dark: true)
    }

    func test_allPasted_dark() {
        snapshot(progress: "Done", preview: "All 3 clips pasted", dark: true)
    }
}
