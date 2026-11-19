// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
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

    private func sampleThumbnail() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 180)).image { context in
            UIColor(red: 0.25, green: 0.55, blue: 0.35, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 180))
            UIColor(red: 0.95, green: 0.78, blue: 0.25, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 75, y: 45, width: 90, height: 90))
        }
        return try #require(image.jpegData(compressionQuality: 0.7))
    }

    @Test("every supported keyboard card kind renders in light and dark")
    func whenAllSupportedKindsRendered_thenLightAndDarkRender() throws {
        try FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
        let thumbnail = try sampleThumbnail()
        let cardSize = KeyboardLayout.cardSize(size: .medium, isRegular: false)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries: [(String, QuickInsertEntry)] = [
            (
                "text",
                QuickInsertEntry(
                    id: UUID(), section: .recent, kind: .text,
                    title: "Pick up basil, pine nuts and parmesan on the way home",
                    text: "Pick up basil, pine nuts and parmesan on the way home",
                    expandsOnInsert: false, date: now, source: "Notes"
                )
            ),
            (
                "titled",
                QuickInsertEntry(
                    id: UUID(), section: .collection, kind: .text,
                    title: "12 Basil Lane", text: "12 Basil Lane", expandsOnInsert: false,
                    customTitle: "Home Address", date: now, source: "Notes"
                )
            ),
            (
                "link",
                QuickInsertEntry(
                    id: UUID(), section: .recent, kind: .url,
                    title: "https://copypesto.net/guide/sync",
                    text: "https://copypesto.net/guide/sync",
                    expandsOnInsert: false, date: now, source: "Safari"
                )
            ),
            (
                "code",
                QuickInsertEntry(
                    id: UUID(), section: .recent, kind: .code,
                    title: "let pesto = basil + garlic", text: "let pesto = basil + garlic + oil",
                    expandsOnInsert: false, date: now, source: "Xcode"
                )
            ),
            (
                "color",
                QuickInsertEntry(
                    id: UUID(), section: .recent, kind: .color,
                    title: "#2F7A49", text: "#2F7A49",
                    expandsOnInsert: false, date: now, source: "Pasted"
                )
            ),
            (
                "snippet",
                QuickInsertEntry(
                    id: UUID(), section: .snippets, kind: .text,
                    title: "Thanks, {{date}}", text: "Thanks, {{date}}",
                    expandsOnInsert: true, date: now, source: "Notes"
                )
            ),
            (
                "picture",
                QuickInsertEntry(
                    id: UUID(), section: .recent, kind: .image,
                    title: "Basil", text: "", expandsOnInsert: false,
                    date: now, source: "Photos", thumbnail: thumbnail
                )
            ),
            (
                "gif",
                QuickInsertEntry(
                    id: UUID(), section: .recent, kind: .image,
                    title: "Gif", text: "", expandsOnInsert: false,
                    date: now, source: "Safari", thumbnail: thumbnail, isAnimated: true
                )
            )
        ]

        for (name, entry) in entries {
            var renders: [Bool: Data] = [:]
            for dark in [false, true] {
                let view = KeyboardClipKey(entry: entry, cardSize: cardSize, feedback: nil)
                    .padding(8)
                    .background(dark ? Color.black : Color(white: 0.9))
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.uiImage)
                #expect(image.size == CGSize(width: cardSize.width + 16, height: cardSize.height + 16), "\(name)")
                let data = try #require(image.pngData())
                renders[dark] = data
                try data.write(to: Self.output.appendingPathComponent("card-\(name)-\(dark ? "dark" : "light").png"))
            }
            if name != "color" {
                #expect(renders[false] != renders[true], "\(name) should differ between light and dark")
            }
        }
    }

    @Test("QuickInsertSelection excludes file clips and secrets")
    func whenQuickInsertSelectionBuilt_thenFileAndSecretsAreExcluded() throws {
        let context = try ModelContext(ModelContainerSetup.makeInMemory())
        let text = ClipboardItem(
            type: .text, previewText: "Plain text", contentHash: UUID().uuidString,
            byteSize: 10, deviceID: "dev", sequenceNumber: 1
        )
        let file = ClipboardItem(
            type: .file, previewText: "file:///Users/me/recipe.pdf", contentHash: UUID().uuidString,
            byteSize: 24, deviceID: "dev", sequenceNumber: 2
        )
        let secret = ClipboardItem(
            type: .text, previewText: "sk-proj-••••••••", sensitivity: .apiKey,
            sensitivityMaskedPreview: "sk-proj-••••••••", contentHash: UUID().uuidString,
            byteSize: 16, deviceID: "dev", sequenceNumber: 3
        )
        context.insert(text)
        context.insert(file)
        context.insert(secret)

        let set = try QuickInsertSelection.set(in: context, now: .now, text: { item in
            switch item.id {
            case text.id: "Plain text"
            case file.id: "file:///Users/me/recipe.pdf"
            case secret.id: "sk-proj-secret"
            default: nil
            }
        })
        #expect(set.entries.map(\.id) == [text.id])
    }
}
