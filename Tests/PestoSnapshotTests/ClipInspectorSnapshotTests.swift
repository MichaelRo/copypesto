// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// The Clip window (ADR 0071): a text clip with a title, note and tags, editable, and as a snippet being made (ADR
/// 0075); and a hidden secret, details only.
@MainActor
final class ClipInspectorSnapshotTests: XCTestCase {
    private func snapshot(
        editable: Bool, secret: Bool, colorScheme: ColorScheme, makingSnippet: Bool = false,
        file: StaticString = #filePath, testName: String = #function, line: UInt = #line
    ) throws {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let collection = Pinboard(name: "Travel", symbolName: "airplane", colorHex: "#4F8A5B", sortOrder: 0)
        context.insert(collection)
        let text = secret ? "••••••••••••" : "Flight LX 1612 lands at 18:40, gate B34. Pick up at arrivals."
        let item = ClipboardItem(
            timestamp: Date(timeIntervalSince1970: 1_750_000_000), type: .text, sourceBundleID: "com.apple.Notes",
            sourceAppName: "Notes", previewText: text,
            contentHash: UUID().uuidString, byteSize: text.utf8.count, deviceID: "test-device", sequenceNumber: 1,
            collectionID: secret ? nil : collection.id
        )
        if secret {
            item.sensitivityRaw = SensitivityCategory.apiKey.rawValue
        } else {
            item.customTitle = "Mom's arrival"
            item.userNote = "Ask about the cheese."
            item.tags = ["travel", "family"]
        }
        context.insert(item)
        try context.save()
        let appState = AppState()
        appState.historyContainer = container
        let model = TextEditModel(
            clipID: item.id, text: editable ? text : "", isMonospaced: false, isEditable: editable
        ) { _, _ in .saved }
        if makingSnippet { model.beginSnippet(title: "Mom's arrival") }
        let size = TextEditWindowController.defaultSize
        let root = ClipInspectorRoot(model: model)
            .frame(width: size.width, height: size.height)
            .background(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
            .environment(appState)
            .defaultAppStorage(AppDefaults.store)
            .preferredColorScheme(colorScheme)
            .inBrandAccent()
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(of: controller, as: .image(size: size), file: file, testName: testName, line: line)
        }
    }

    func test_whenTextClip_thenTitleTextAndDetailsShow() throws {
        try snapshot(editable: true, secret: false, colorScheme: .light)
    }

    func test_whenTextClipInDark_thenTitleTextAndDetailsShow() throws {
        try snapshot(editable: true, secret: false, colorScheme: .dark)
    }

    func test_whenMakingSnippet_thenTheSnippetEditorTakesTheTextPane() throws {
        try snapshot(editable: true, secret: false, colorScheme: .light, makingSnippet: true)
    }

    func test_whenHiddenSecret_thenOnlyDetailsShow() throws {
        try snapshot(editable: false, secret: true, colorScheme: .light)
    }
}
