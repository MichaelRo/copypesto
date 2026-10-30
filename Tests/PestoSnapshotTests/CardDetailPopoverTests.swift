// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// The hover card for each kind of clip, in light and dark. Baselines are OS-specific (see `ClipboardCardTests`).
@MainActor
final class CardDetailPopoverTests: XCTestCase {
    private func makeItem(_ type: ClipboardType, preview: String, language: String? = nil) throws -> ClipboardItem {
        let container = try ModelContainerSetup.makeInMemory()
        let ctx = ModelContext(container)
        let item = ClipboardItem(
            type: type, sourceAppName: "Xcode", previewText: preview, contentHash: UUID().uuidString,
            byteSize: preview.utf8.count, deviceID: "test-device", sequenceNumber: 1
        )
        item.detectedLanguage = language
        item.timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        ctx.insert(item)
        return item
    }

    private func snapshot(
        _ item: ClipboardItem, collection: String? = nil, scheme: ColorScheme = .light,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) {
        let root = CardDetailPopover(item: item, collectionName: collection)
            .padding(20)
            .background(scheme == .light ? Color(red: 0.92, green: 0.85, blue: 0.71) : Color(white: 0.13))
            .environment(\.colorScheme, scheme)
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(
                of: controller, as: .image(size: CGSize(width: 360, height: 420)),
                file: file, testName: testName, line: line
            )
        }
    }

    func test_text() throws {
        try snapshot(makeItem(
            .text,
            preview: "Dinner is at 7:30. Bring the basil from the balcony, the good olive oil."
        ))
    }

    func test_text_dark() throws {
        try snapshot(
            makeItem(.text, preview: "Dinner is at 7:30. Bring the basil from the balcony."), collection: "Recipes",
            scheme: .dark
        )
    }

    func test_code() throws {
        try snapshot(makeItem(
            .code,
            preview: "def pesto(basil, nuts, oil=0.5):\n    paste = grind(basil + nuts)\n    return paste.fold(oil)",
            language: "Python"
        ))
    }

    func test_code_longLine_fadesAtTheRightEdge() throws {
        let line = "let recipe = Recipe(name: \"Pesto\", ingredients: [\"basil\", \"pine nuts\", \"parmesan\"])"
        try snapshot(makeItem(.code, preview: line + "\nprint(recipe)", language: "Swift"))
    }

    func test_code_dark() throws {
        try snapshot(
            makeItem(.code, preview: "func pesto() -> Int {\n    return 42\n}", language: "Swift"), scheme: .dark
        )
    }

    func test_longText_scrollsInsideTheCap() throws {
        let sentence = "Start the pine nuts in a dry pan and do not walk away. "
        try snapshot(makeItem(.text, preview: String(repeating: sentence, count: 14)))
    }

    func test_link() throws {
        try snapshot(makeItem(.url, preview: "https://kitchen.example/recipes/pesto"))
    }

    func test_color() throws {
        try snapshot(makeItem(.color, preview: "#529D6E"))
    }

    func test_secret() throws {
        let container = try ModelContainerSetup.makeInMemory()
        let ctx = ModelContext(container)
        let item = ClipboardItem(
            type: .text, sourceAppName: "Terminal", previewText: "API key •••• (40 characters hidden)",
            sensitivity: .apiKey, sensitivityMaskedPreview: "API key •••• (40 characters hidden)",
            contentHash: UUID().uuidString, byteSize: 40, deviceID: "test-device", sequenceNumber: 1
        )
        item.timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        ctx.insert(item)
        snapshot(item)
    }
}
