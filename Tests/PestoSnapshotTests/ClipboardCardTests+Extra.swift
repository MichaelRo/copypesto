// SPDX-License-Identifier: MIT

import SwiftUI
import XCTest
@testable import Pesto
@testable import PestoCore

extension ClipboardCardTests {
    func test_titledCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "12 Basil Lane, Apt 4B")
        item.customTitle = "Home Address"
        snapshotCard(ClipboardCard(item: item, inCollection: true))
        snapshotCard(ClipboardCard(item: item, inCollection: true), named: "light", colorScheme: .light)
    }

    func test_snippetCard() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "Thanks, {{date}}")
        snapshotCard(ClipboardCard(item: item))
        snapshotCard(ClipboardCard(item: item), named: "light", colorScheme: .light)
    }

    func test_shortCoveredText_showsTheCoverFace() throws {
        let ctx = try makeContext()
        let item = makeItem(in: ctx, type: .text, preview: "hunter2")
        snapshotCard(ClipboardCard(item: item, isPrivacyBlurred: true))
    }
}
