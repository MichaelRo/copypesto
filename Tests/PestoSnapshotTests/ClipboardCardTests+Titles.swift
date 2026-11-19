// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

@MainActor
extension ClipboardCardTests {
    func test_titledTextCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: Self.longText)
        item.sourceAppName = "Notes"
        item.customTitle = "Release notes"
        snapshotCard(ClipboardCard(item: item))
        snapshotCard(ClipboardCard(item: item), named: "light", colorScheme: .light)
    }

    func test_titledSnippetCard() throws {
        let ctx = try makeContext()
        let sql = "SELECT id, title, updated_at\nFROM clips\nWHERE collection = {{collection}}\n"
            + "ORDER BY updated_at DESC\nLIMIT 25;"
        let item = makeItem(in: ctx, type: .code, preview: sql, isPinned: true)
        item.sourceAppName = "Xcode"
        item.customTitle = "Pinned clips query"
        snapshotCard(ClipboardCard(item: item))
    }

    func test_titledLargeTextCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Meeting at 3pm in Studio B")
        item.sourceAppName = "Slack"
        item.customTitle = "Standup"
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1))
    }

    func test_titledLinkCard() throws {
        let ctx = try makeContext()
        let item = makeItem(
            in: ctx,
            type: .url,
            preview: "https://developer.apple.com/documentation/swiftui/view"
        )
        item.sourceAppName = "Safari"
        item.customTitle = "SwiftUI View Docs"
        snapshotCard(ClipboardCard(item: item))
    }

    func test_titledPictureCard() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.0, source: "Preview")
        item.customTitle = "Hero banner"
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1))
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1), named: "light", colorScheme: .light)
    }

    func test_titledColorCard() throws {
        let ctx = try makeContext()
        let darkFill = makeItem(in: ctx, type: .color, preview: "#2F7A49")
        darkFill.sourceAppName = "ColorSync Utility"
        darkFill.customTitle = "Basil accent"
        snapshotCard(ClipboardCard(item: darkFill))

        let lightFill = makeItem(in: ctx, type: .color, preview: "#C9A227")
        lightFill.sourceAppName = "Digital Color Meter"
        lightFill.customTitle = "Parmesan gold"
        snapshotCard(ClipboardCard(item: lightFill), named: "lightInk", colorScheme: .light)
    }

    func test_collectionLinkCard_customTitleAndOGTitle() throws {
        let ctx = try makeContext()
        let item = makeItem(
            in: ctx,
            type: .url,
            preview: "https://developer.apple.com/documentation/swiftui/view"
        )
        item.sourceAppName = "Safari"
        item.customTitle = "SwiftUI View Docs"
        item.ogTitle = "View | Apple Developer Documentation"
        item.ogSiteName = "Apple Developer"
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1, inCollection: true))
    }

    func test_collectionLinkCard_ogTitleOnly() throws {
        let ctx = try makeContext()
        let item = makeItem(
            in: ctx,
            type: .url,
            preview: "https://developer.apple.com/documentation/swiftui/view"
        )
        item.sourceAppName = "Safari"
        item.ogTitle = "View | Apple Developer Documentation"
        item.ogSiteName = "Apple Developer"
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1, inCollection: true))
    }

    func test_collectionLinkCard_customTitleOnly() throws {
        let ctx = try makeContext()
        let item = makeItem(
            in: ctx,
            type: .url,
            preview: "https://developer.apple.com/documentation/swiftui/view"
        )
        item.sourceAppName = "Safari"
        item.customTitle = "SwiftUI View Docs"
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1, inCollection: true))
    }

    func test_collectionPictureCard_fittedWithTitle() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.5, source: "Preview")
        item.customTitle = "Boarding pass"
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1, inCollection: true))
    }

    func test_collectionColorCard_withTitle() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .color, preview: "#2F7A49")
        item.sourceAppName = "ColorSync Utility"
        item.customTitle = "Basil accent"
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1, inCollection: true))
    }
}
