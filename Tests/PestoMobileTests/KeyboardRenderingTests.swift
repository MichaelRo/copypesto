// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import PestoCore

/// Draws the keyboard in each state, iPhone and iPad width, light and dark, and writes the pictures to
/// `.build/keyboard-renders` beside the repository so a person (or an agent) can look at them.
@Suite("The keyboard draws each state")
@MainActor
struct KeyboardRenderingTests {
    private static let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/keyboard-renders", isDirectory: true)

    private static let standup = QuickInsertEntry(
        id: UUID(), section: .collection, kind: .text, title: "Standup notes: blockers first, then demos",
        text: "Standup notes: blockers first, then demos", expandsOnInsert: false, fromAnotherDevice: true
    )

    private static let set = QuickInsertSet(createdAt: .now, entries: [
        standup,
        QuickInsertEntry(
            id: UUID(), section: .pinned, kind: .text, title: "Home", text: "12 Basil Lane", expandsOnInsert: false
        ),
        QuickInsertEntry(
            id: UUID(), section: .snippets, kind: .text, title: "Thanks, {{date}}", text: "Thanks, {{date}}",
            expandsOnInsert: true
        ),
        QuickInsertEntry(
            id: UUID(), section: .recent, kind: .url, title: "https://copypesto.net/guide/sync",
            text: "https://copypesto.net/guide/sync", expandsOnInsert: false
        ),
        QuickInsertEntry(
            id: UUID(), section: .recent, kind: .text, title: "Pick up basil, pine nuts and parmesan on the way home",
            text: "Pick up basil, pine nuts and parmesan on the way home", expandsOnInsert: false
        )
    ], collections: [
        QuickInsertCollection(id: UUID(), name: "Work", symbolName: "briefcase", entryIDs: [standup.id])
    ])

    private static let menus: [(String, KeyboardMenu)] = [
        ("restricted", KeyboardMenu(hasFullAccess: false) { set }),
        ("unavailable", KeyboardMenu(hasFullAccess: true) { nil }),
        ("empty", KeyboardMenu(hasFullAccess: true) { .empty }),
        ("ready", KeyboardMenu(hasFullAccess: true) { set })
    ]

    /// Hosted in a real window of the app's scene: `ImageRenderer` draws the scroll views, the segmented filter and
    /// the Globe key as placeholders, because they are UIKit underneath.
    private func render(
        _ menu: KeyboardMenu, width: CGFloat, regular: Bool, dark: Bool, word: String? = nil, search: String? = nil
    ) async throws
    -> UIImage {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "the hosted test runs inside the app, which has a window scene"
        )
        let model = KeyboardModel()
        model.menu = menu
        model.word = word
        if let search {
            model.openSearch()
            model.typeInSearch(search)
        }
        let keys = KeyboardKeys(
            insert: { _ in }, deleteBackward: {}, switchKeyboard: {}, contextBefore: { nil }, contextAfter: { nil },
            relayout: {}
        )
        let size = CGSize(
            width: width,
            height: (regular ? 300 : 280) + (search == nil ? 0 : KeyboardModel.searchExtraHeight)
        )
        let host = UIHostingController(rootView: KeyboardRootView(model: model, keys: keys, controller: nil))
        host.view.backgroundColor = .systemGroupedBackground
        // An input view sits below the text field, outside the status bar and home indicator insets of a window.
        host.safeAreaRegions = []
        host.traitOverrides.horizontalSizeClass = regular ? .regular : .compact
        host.overrideUserInterfaceStyle = dark ? .dark : .light
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<5 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    @Test("every state draws at iPhone and iPad width, light and dark, and the pictures are written out")
    func whenDrawn_thenEveryStateRenders() async throws {
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        for (name, menu) in Self.menus {
            for (device, width, regular) in [("iphone", CGFloat(402), false), ("ipad", CGFloat(820), true)] {
                for dark in [false, true] {
                    let image = try await render(menu, width: width, regular: regular, dark: dark)
                    #expect(image.size == CGSize(width: width, height: regular ? 300 : 280), "\(name) \(device)")
                    let data = try #require(image.pngData())
                    let file = "\(name)-\(device)-\(dark ? "dark" : "light").png"
                    try data.write(to: Self.output.appendingPathComponent(file))
                }
            }
        }
    }

    @Test("the word typed before switching narrows the row and leads the chips")
    func whenAWordWasTyped_thenTheRowShowsItsMatches() async throws {
        let menu = Self.menus[3].1
        #expect(menu.entries(matching: "basil").count == 2)
        for dark in [false, true] {
            let image = try await render(menu, width: 402, regular: false, dark: dark, word: "basil")
            let data = try #require(image.pngData())
            try data.write(to: Self.output.appendingPathComponent("matching-iphone-\(dark ? "dark" : "light").png"))
        }
    }

    @Test("the search page draws its field, the matching row and the letters, empty and with a query")
    func whenSearching_thenThePageDraws() async throws {
        let menu = Self.menus[3].1
        for (name, search) in [("search-empty", ""), ("search-basil", "basil")] {
            for dark in [false, true] {
                let image = try await render(menu, width: 402, regular: false, dark: dark, search: search)
                let data = try #require(image.pngData())
                try data.write(to: Self.output.appendingPathComponent("\(name)-iphone-\(dark ? "dark" : "light").png"))
            }
        }
    }

    @Test("the clips replace the note once the set is ready")
    func whenReady_thenThePictureDiffersFromRestricted() async throws {
        let restricted = try await render(Self.menus[0].1, width: 402, regular: false, dark: false).pngData()
        let ready = try await render(Self.menus[3].1, width: 402, regular: false, dark: false).pngData()
        #expect(restricted != ready)
    }

    @Test("KeyboardLayout matches iPhone and iPad card sizes and row counts")
    func whenKeyboardLayoutQueried_thenSizesMatchSpec() {
        #expect(KeyboardLayout.rows(size: .small, isRegular: false, isLandscape: false) == 1)
        #expect(KeyboardLayout.rows(size: .medium, isRegular: false, isLandscape: false) == 2)
        #expect(KeyboardLayout.rows(size: .large, isRegular: false, isLandscape: false) == 2)
        #expect(KeyboardLayout.rows(size: .medium, isRegular: false, isLandscape: true) == 1)
        #expect(KeyboardLayout.rows(size: .large, isRegular: false, isLandscape: true) == 1)
        #expect(KeyboardLayout.rows(size: .large, isRegular: true, isLandscape: false) == 1)

        #expect(KeyboardLayout.cardSize(size: .medium, isRegular: false) == CGSize(width: 150, height: 88))
        #expect(KeyboardLayout.cardSize(size: .large, isRegular: false) == CGSize(width: 180, height: 110))
        #expect(KeyboardLayout.cardSize(size: .small, isRegular: true).width == 180)
        #expect(KeyboardLayout.cardSize(size: .medium, isRegular: true).width == 228)
        #expect(KeyboardLayout.cardSize(size: .large, isRegular: true).width == 260)
    }
}
