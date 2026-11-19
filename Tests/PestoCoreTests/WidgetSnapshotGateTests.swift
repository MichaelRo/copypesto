// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("What the Mac's widget snapshot may hold")
struct WidgetSnapshotGateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("the lock switched on is Locked, covered contents are Hidden, the lock wins, otherwise the clips")
    func whenLockOrCoverChange_thenTheGateFollows() {
        #expect(WidgetSnapshotGate.decide(lockEnabled: false, isCovered: false) == .clips)
        #expect(WidgetSnapshotGate.decide(lockEnabled: true, isCovered: false) == .locked)
        #expect(WidgetSnapshotGate.decide(lockEnabled: false, isCovered: true) == .hidden)
        #expect(WidgetSnapshotGate.decide(lockEnabled: true, isCovered: true) == .locked)
    }

    @Test("a placeholder holds no clip and says why; the clips have none")
    func whenAPlaceholderIsMade_thenItCarriesNoClip() throws {
        #expect(WidgetSnapshotGate.clips.placeholder(theme: .brand, at: now) == nil)
        let locked = try #require(WidgetSnapshotGate.locked.placeholder(theme: .brand, at: now))
        let hidden = try #require(WidgetSnapshotGate.hidden.placeholder(theme: .brand, at: now))
        #expect(locked.isLocked && !locked.isHidden && locked.clips.isEmpty && locked.pinned.isEmpty)
        #expect(hidden.isHidden && !hidden.isLocked && hidden.clips.isEmpty && hidden.pinned.isEmpty)
    }

    @Test("the theme is resolved for both appearances as the app draws it, Basil by default")
    func whenTheThemeIsResolved_thenBothAppearancesFollow() {
        let basil = WidgetSnapshot.Theme.resolve(accent: AccentChoice.defaultStored, theme: "basil", darkTheme: "")
        #expect(basil == .brand)
        let pine = WidgetSnapshot.Theme.resolve(accent: AccentChoice.defaultStored, theme: "pineNut", darkTheme: "")
        #expect(pine.lightAccent == AppTheme.pineNut.accentHex(dark: false))
        #expect(pine.darkGround == AppTheme.pineNut.groundHex(dark: true))
    }
}
