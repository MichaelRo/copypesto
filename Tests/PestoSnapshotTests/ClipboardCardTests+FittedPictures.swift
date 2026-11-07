// SPDX-License-Identifier: MIT
import PestoCore
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Pesto

@MainActor
extension ClipboardCardTests {
    func test_pictureCard_wideIsShownWholeOverABlurredCopy() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 1.5, source: "Preview")
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1))
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 1), named: "light", colorScheme: .light)
    }

    func test_pictureCard_tallScreenshotIsFitted() throws {
        defer { ThumbnailCache.shared.clear() }
        let ctx = try makeContext()
        let item = pictureItem(in: ctx, aspect: 0.4, source: "Screenshot")
        snapshotCard(ClipboardCard(item: item, shortcutNumber: 3))
    }
}
