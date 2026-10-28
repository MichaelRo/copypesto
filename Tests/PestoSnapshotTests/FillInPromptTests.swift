// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Pesto

/// The prompt a snippet shows when it asks for values (ADR 0017), in light and dark. Baselines are OS-specific (see
/// `ClipboardCardTests`).
@MainActor
final class FillInPromptTests: XCTestCase {
    private func snapshot(
        _ template: String, title: String, scheme: ColorScheme, height: CGFloat,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        let fields = FillInParser.fields(in: template)
        let model = FillInPromptModel(title: title, fields: fields, fills: SnippetFills.initial(for: fields))
        let root = FillInPromptView(model: model)
            .padding(24)
            .background(scheme == .light ? Color(red: 0.92, green: 0.85, blue: 0.71) : Color(white: 0.13))
            .environment(\.colorScheme, scheme)
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(
                of: controller, as: .image(size: CGSize(width: 400, height: height)),
                file: file, testName: testName, line: line
            )
        }
    }

    private let full = """
    Hi {{input:Customer name default="Ana"}}, {{choice:Tone options="warm|formal"}}
    {{input:Notes multiline}}{{optional:P.S.}}Thanks again!{{/optional}}
    """

    func test_allKindsOfField_light() {
        snapshot(full, title: "Reply to a customer", scheme: .light, height: 400)
    }

    func test_allKindsOfField_dark() {
        snapshot(full, title: "Reply to a customer", scheme: .dark, height: 400)
    }

    func test_oneField_light() {
        snapshot("Order {{input:Order number}}", title: "Order status", scheme: .light, height: 190)
    }
}
