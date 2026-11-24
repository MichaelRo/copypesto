// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("What the Lock Screen widget may show")
struct LockScreenWidgetContentTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var sampleSnapshot: WidgetSnapshot {
        let clip = WidgetClip(
            id: UUID(), kind: .text, text: "12 Basil Lane", source: "Notes", date: now - 30
        )
        let pinned = WidgetClip(
            id: UUID(), kind: .text, text: "Gate B7", source: "Mail", date: now - 120, isPinned: true
        )
        let work = WidgetCollection(id: UUID(), name: "Work", symbolName: "briefcase", colorHex: "#2F8B4C")
        return WidgetSnapshot(
            createdAt: now, theme: .brand, clips: [clip], pinned: [pinned], collections: [work],
            collectionClipIDs: [work.id: [pinned.id]], collectionClips: [pinned]
        )
    }

    @Test("off by default: showsClipsOnLockScreen false hides every clip and even Locked state")
    func whenOptInIsOff_thenOptInRequiredAlwaysWins() {
        let full = sampleSnapshot
        for snapshot in [
            full,
            .locked(theme: .brand, at: now),
            .empty(theme: .brand, at: now),
            nil
        ] as [WidgetSnapshot?] {
            let content = LockScreenWidgetContent(snapshot: snapshot, showsClipsOnLockScreen: false, source: .recent)
            #expect(content.state == .optInRequired)
            #expect(content.collection == nil)
            #expect(content.tapURL == nil)
        }
    }

    @Test("opted in: locked, empty, missing collection and unavailable follow WidgetContent")
    func whenOptInIsOn_thenStatesFollowSnapshot() {
        let full = sampleSnapshot
        let clip = full.clips[0]

        let ready = LockScreenWidgetContent(snapshot: full, showsClipsOnLockScreen: true, source: .recent)
        #expect(ready.state == .clip(clip))
        #expect(ready.action == .copy)
        #expect(ready.tapURL == WidgetLink.url(for: clip.id))

        let locked = LockScreenWidgetContent(
            snapshot: .locked(theme: .brand, at: now), showsClipsOnLockScreen: true, source: .recent
        )
        #expect(locked.state == .locked)
        #expect(locked.tapURL == AppLink.url(for: .unlock))

        let unavailable = LockScreenWidgetContent(snapshot: nil, showsClipsOnLockScreen: true, source: .recent)
        #expect(unavailable.state == .unavailable)
        #expect(unavailable.tapURL == nil)

        let empty = LockScreenWidgetContent(
            snapshot: .empty(theme: .brand, at: now), showsClipsOnLockScreen: true, source: .recent
        )
        #expect(empty.state == .empty)
        #expect(empty.tapURL == nil)

        let noCollection = LockScreenWidgetContent(
            snapshot: full, showsClipsOnLockScreen: true, source: .collection(UUID())
        )
        #expect(noCollection.state == .noCollection)
        #expect(noCollection.tapURL == nil)
    }

    @Test("opted in with pinned or collection source picks the first clip from that source")
    func whenOptInIsOnWithSource_thenPicksFirstClipFromSource() {
        let full = sampleSnapshot
        let workID = full.collections[0].id
        let pinned = full.pinned[0]

        let fromPinned = LockScreenWidgetContent(snapshot: full, showsClipsOnLockScreen: true, source: .pinned)
        #expect(fromPinned.state == .clip(pinned))

        let fromCollection = LockScreenWidgetContent(
            snapshot: full, showsClipsOnLockScreen: true, source: .collection(workID)
        )
        #expect(fromCollection.state == .clip(pinned))
        #expect(fromCollection.collection?.id == workID)

        let hidden = LockScreenWidgetContent(
            snapshot: .hidden(theme: .brand, at: now), showsClipsOnLockScreen: true, source: .recent
        )
        #expect(hidden.state == .hidden)
        #expect(hidden.tapURL == nil)

        let unchosenCollection = LockScreenWidgetContent(
            snapshot: full, showsClipsOnLockScreen: true, source: .collection(nil)
        )
        #expect(unchosenCollection.state == .noCollection)

        let noPins = WidgetSnapshot(createdAt: now, theme: .brand, clips: full.clips, pinned: [])
        #expect(LockScreenWidgetContent(snapshot: noPins, showsClipsOnLockScreen: true, source: .pinned)
            .state == .empty)
    }

    @Test("snapshot expiresAt transitions widget content to locked once reached")
    func whenSnapshotExpires_thenBecomesLocked() {
        let base = sampleSnapshot
        let expiresAt = now + 300
        let expiring = base.withExpiresAt(expiresAt)

        let before = LockScreenWidgetContent(
            snapshot: expiring, showsClipsOnLockScreen: true, source: .recent, now: now + 299
        )
        #expect(before.state == .clip(base.clips[0]))
        #expect(WidgetContent(snapshot: expiring, size: .small, now: now + 299).state == .clips)

        let atExpiry = LockScreenWidgetContent(
            snapshot: expiring, showsClipsOnLockScreen: true, source: .recent, now: expiresAt
        )
        #expect(atExpiry.state == .locked)
        #expect(atExpiry.tapURL == AppLink.url(for: .unlock))
        #expect(WidgetContent(snapshot: expiring, size: .small, now: expiresAt).state == .locked)
    }

    @Test("When Chosen action maps Copy Clip, Open Pesto, and Open Clip tap URLs while Locked always unlocks")
    func whenActionConfigured_thenTapURLFollowsAction() {
        let base = sampleSnapshot
        let clip = base.clips[0]

        let copyContent = LockScreenWidgetContent(
            snapshot: base, showsClipsOnLockScreen: true, source: .recent, action: .copy, now: now
        )
        #expect(copyContent.tapURL == WidgetLink.url(for: clip.id))

        let openPestoContent = LockScreenWidgetContent(
            snapshot: base, showsClipsOnLockScreen: true, source: .recent, action: .openPesto, now: now
        )
        #expect(openPestoContent.tapURL == nil)

        let openClipContent = LockScreenWidgetContent(
            snapshot: base, showsClipsOnLockScreen: true, source: .recent, action: .openClip, now: now
        )
        #expect(openClipContent.tapURL == WidgetLink.url(for: clip.id, action: .show))

        for action in LockScreenWidgetContent.Action.allCases {
            let locked = LockScreenWidgetContent(
                snapshot: .locked(theme: .brand, at: now),
                showsClipsOnLockScreen: true,
                source: .recent,
                action: action,
                now: now
            )
            #expect(locked.tapURL == AppLink.url(for: .unlock))
        }
    }
}
