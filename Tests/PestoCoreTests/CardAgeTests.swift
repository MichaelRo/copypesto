// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("The age a card shows")
struct CardAgeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func pastedClip() throws -> ClipboardItem {
        let container = try ModelContainerSetup.makeInMemory()
        let context = ModelContext(container)
        let item = ClipboardItem(
            type: .text, previewText: "a", contentHash: "a", byteSize: 1, deviceID: "t", sequenceNumber: 1
        )
        item.timestamp = now.addingTimeInterval(-3 * 86_400)
        context.insert(item)
        item.bringToFront(at: now.addingTimeInterval(-120))
        return item
    }

    @Test("outside a collection a card shows when the clip was last used")
    func whenInHistory_thenLastUse() throws {
        let item = try pastedClip()
        #expect(CardAge.text(for: item, inCollection: false, now: now) == "2m ago")
    }

    @Test("inside a collection a card shows when the clip was first copied, so a paste does not change it")
    func whenInCollection_thenFirstCopy() throws {
        let item = try pastedClip()
        #expect(CardAge.text(for: item, inCollection: true, now: now) == "3d ago")
    }

    @Test("the text steps from just now to minutes, hours and days")
    func whenIntervalsGrow_thenUnitsStep() {
        #expect(CardAge.text(interval: 30) == "just now")
        #expect(CardAge.text(interval: 60) == "1m ago")
        #expect(CardAge.text(interval: 3599) == "59m ago")
        #expect(CardAge.text(interval: 3600) == "1h ago")
        #expect(CardAge.text(interval: 86_400) == "1d ago")
        #expect(CardAge.text(interval: -5) == "just now")
    }

    @Test("the interval VoiceOver reads follows the same basis")
    func whenInCollection_thenIntervalUsesFirstCopy() throws {
        let item = try pastedClip()
        #expect(CardAge.interval(for: item, inCollection: true, now: now) == 3 * 86_400)
        #expect(CardAge.interval(for: item, inCollection: false, now: now) == 120)
    }
}
