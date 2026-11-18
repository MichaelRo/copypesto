// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("What each widget family draws")
struct WidgetContentTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(clips count: Int) -> WidgetSnapshot {
        let clips = (0..<count).map { index in
            WidgetClip(id: UUID(), kind: .text, text: "clip \(index)", date: now - Double(index) * 90)
        }
        return WidgetSnapshot(createdAt: now, theme: .brand, clips: clips)
    }

    @Test("small shows the latest clip, medium three, large six, fewer at an accessibility text size")
    func whenTheFamilyDiffers_thenTheCountFollows() {
        let full = snapshot(clips: 8)

        #expect(WidgetContent(snapshot: full, size: .small).clips.map(\.text) == ["clip 0"])
        #expect(WidgetContent(snapshot: full, size: .medium).clips.count == 3)
        #expect(WidgetContent(snapshot: full, size: .large).clips.count == 6)
        #expect(WidgetContent(snapshot: full, size: .medium, accessibilityText: true).clips.count == 2)
        #expect(WidgetContent(snapshot: full, size: .large, accessibilityText: true).clips.count == 4)
        #expect(WidgetSize.large.columns(accessibilityText: false) == 2)
        #expect(WidgetSize.medium.columns(accessibilityText: false) == 3)
        #expect(WidgetContent(snapshot: snapshot(clips: 2), size: .large).clips.count == 2)
        for size in WidgetSize.allCases {
            #expect(WidgetContent(snapshot: full, size: size).state == .clips)
        }
    }

    @Test("a widget set to Pinned shows the pinned list, and says No clips yet when there is none")
    func whenSetToPinned_thenThePinnedListIsShown() {
        let pin = WidgetClip(id: UUID(), kind: .text, text: "pinned", date: now, isPinned: true)
        let snapshot = WidgetSnapshot(createdAt: now, theme: .brand, clips: snapshot(clips: 3).clips, pinned: [pin])

        #expect(WidgetContent(snapshot: snapshot, size: .large, source: .pinned).clips == [pin])
        #expect(snapshot.clip(id: pin.id) == pin)
        let none = WidgetSnapshot(createdAt: now, theme: .brand, clips: snapshot.clips)
        #expect(WidgetContent(snapshot: none, size: .medium, source: .pinned).state == .empty)
    }

    @Test("no snapshot is unavailable in the brand's colors; an empty one is empty in its own theme")
    func whenThereIsNothingToShow_thenTheStateSaysWhy() {
        let theme = WidgetSnapshot.Theme(
            lightGround: "FFFFFF", darkGround: "000000", lightAccent: "8A4F16", darkAccent: "E2A15E"
        )
        let unavailable = WidgetContent(snapshot: nil, size: .medium)
        let empty = WidgetContent(snapshot: .empty(theme: theme, at: now), size: .medium)

        #expect(unavailable.state == .unavailable)
        #expect(unavailable.theme == .brand)
        #expect(unavailable.clips.isEmpty)
        #expect(empty.state == .empty)
        #expect(empty.theme == theme)
    }

    @Test("a locked snapshot says Locked and shows no clip; a snapshot written before the field decodes as unlocked")
    func whenLocked_thenTheStateIsLocked() throws {
        let locked = WidgetSnapshot.locked(theme: .brand, at: now)
        let content = WidgetContent(snapshot: locked, size: .large)
        #expect(content.state == .locked)
        #expect(content.clips.isEmpty)

        let json = #"{"createdAt":0,"theme":{"lightGround":"FFFFFF","darkGround":"000000","#
            + #""lightAccent":"8A4F16","darkAccent":"E2A15E"},"clips":[],"pinned":[]}"#
        let old = Data(json.utf8)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: old)
        #expect(!decoded.isLocked)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(locked)).isLocked)
    }

    @Test("the timeline has an entry each time an age reads differently, soonest first and bounded")
    func whenAgesMove_thenTheEntriesFollow() {
        let fresh = WidgetClip(id: UUID(), kind: .text, text: "a", date: now - 30)
        let hourOld = WidgetClip(id: UUID(), kind: .text, text: "b", date: now - 3700)

        let dates = WidgetContent.refreshDates(for: [fresh, hourOld], after: now, limit: 5)

        #expect(dates == [now + 30, now + 90, now + 150, now + 210, now + 270])
        #expect(CardAge.text(interval: dates[0].timeIntervalSince(fresh.date)) == "1m ago")
        #expect(WidgetContent.refreshDates(for: [hourOld], after: now, limit: 2) == [now + 3500, now + 7100])
        #expect(WidgetContent.refreshDates(for: [], after: now).isEmpty)
    }
}
