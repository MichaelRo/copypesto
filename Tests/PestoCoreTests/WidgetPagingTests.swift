// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("A widget's grid and its pages")
struct WidgetPagingTests {
    @Test("each family has a grid near the card's shape, and fewer tiles at an accessibility text size")
    func whenFamily_thenItsGrid() {
        #expect(WidgetSize.small.grid(accessibilityText: false) == .init(rows: 1, columns: 1))
        #expect(WidgetSize.medium.grid(accessibilityText: false) == .init(rows: 1, columns: 2))
        #expect(WidgetSize.large.grid(accessibilityText: false) == .init(rows: 2, columns: 2))
        #expect(WidgetSize.extraLarge.grid(accessibilityText: false) == .init(rows: 2, columns: 4))
        #expect(WidgetSize.medium.clipCount(accessibilityText: true) == 1)
        #expect(WidgetSize.large.clipCount(accessibilityText: true) == 2)
        for size in WidgetSize.allCases {
            #expect(size.clipCount(accessibilityText: true) <= size.clipCount(accessibilityText: false))
        }
    }

    @Test("medium and large page through the list; small and extra large never page")
    func whenPaging_thenCountsAndSlices() {
        #expect(WidgetSize.medium.pageCount(of: 8, accessibilityText: false) == 4)
        #expect(WidgetSize.large.pageCount(of: 8, accessibilityText: false) == 2)
        #expect(WidgetSize.large.pageCount(of: 5, accessibilityText: false) == 2)
        #expect(WidgetSize.small.pageCount(of: 8, accessibilityText: false) == 1)
        #expect(WidgetSize.extraLarge.pageCount(of: 20, accessibilityText: false) == 1)
        #expect(WidgetSize.medium.pageCount(of: 0, accessibilityText: false) == 1)
    }

    @Test("a stored page is clamped, and goes back to the first after a newer snapshot or ten minutes")
    func whenStored_thenThePageIsCurrent() {
        let now = Date(timeIntervalSince1970: 10_000)
        let stored = WidgetPaging.Stored(page: 3, setAt: now - 60, snapshotCreatedAt: now - 120)
        #expect(WidgetPaging.page(stored: stored, snapshotCreatedAt: now - 120, pageCount: 4, now: now) == 3)
        #expect(WidgetPaging.page(stored: stored, snapshotCreatedAt: now - 120, pageCount: 2, now: now) == 1)
        #expect(WidgetPaging.page(stored: stored, snapshotCreatedAt: now - 10, pageCount: 4, now: now) == 0)
        #expect(WidgetPaging.page(stored: stored, snapshotCreatedAt: now - 120, pageCount: 4, now: now + 600) == 0)
        #expect(WidgetPaging.page(stored: nil, snapshotCreatedAt: now, pageCount: 4, now: now) == 0)
    }

    @Test("next and previous wrap around, and the stored pages round-trip through their text")
    func whenStepping_thenItWraps() {
        #expect(WidgetPaging.step(from: 3, by: 1, pageCount: 4) == 0)
        #expect(WidgetPaging.step(from: 0, by: -1, pageCount: 4) == 3)
        #expect(WidgetPaging.step(from: 0, by: 1, pageCount: 1) == 0)
        let now = Date(timeIntervalSince1970: 10_000)
        var pages = WidgetPaging.Pages()
        pages["recent|medium"] = .init(page: 2, setAt: now, snapshotCreatedAt: now)
        let decoded = WidgetPaging.Pages(text: pages.text)
        #expect(decoded["recent|medium"]?.page == 2)
        #expect(WidgetPaging.Pages(text: "not json")["x"] == nil)
    }

    @Test("content shows the page it is asked for")
    func whenContentPaged_thenItSlices() {
        let clips = (0..<8).map { index in
            WidgetClip(
                id: UUID(), kind: .text, text: "clip \(index)", date: Date(timeIntervalSince1970: Double(100 - index))
            )
        }
        let snapshot = WidgetSnapshot(createdAt: .now, theme: .brand, clips: clips)
        let second = WidgetContent(snapshot: snapshot, size: .large, page: 1)
        #expect(second.clips.map(\.text) == ["clip 4", "clip 5", "clip 6", "clip 7"])
        #expect(second.page == 1 && second.pageCount == 2)
        let clamped = WidgetContent(snapshot: snapshot, size: .large, page: 9)
        #expect(clamped.page == 1)
    }
}
