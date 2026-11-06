// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The shelf's surface")
struct ShelfSurfaceTests {
    @Test("nothing stored, or something unknown, is solid")
    func whenNothingValidIsStored_thenSolid() {
        #expect(ShelfSurface(stored: "") == .solid)
        #expect(ShelfSurface(stored: "frosted") == .solid)
        #expect(ShelfSurface(stored: "glass") == .glass)
        #expect(ShelfSurface(stored: "solid") == .solid)
        #expect(Setting.shelfSurface.defaultValue == ShelfSurface.solid.rawValue)
    }

    @Test("glass is drawn only when it is chosen and the Mac is not reducing transparency")
    func whenReduceTransparencyIsOn_thenNeverGlass() {
        #expect(ShelfSurface.drawsGlass(stored: "glass", reduceTransparency: false))
        #expect(!ShelfSurface.drawsGlass(stored: "glass", reduceTransparency: true))
        #expect(!ShelfSurface.drawsGlass(stored: "solid", reduceTransparency: false))
        #expect(!ShelfSurface.drawsGlass(stored: "", reduceTransparency: false))
    }

    @Test("the person reads Glass and Solid, in that order")
    func whenListed_thenGlassThenSolid() {
        #expect(ShelfSurface.allCases.map(\.title) == ["Glass", "Solid"])
    }

    @Test("the wash keeps its three corners on glass and is a third as strong on solid")
    func whenSolid_thenTheWashIsSoft() {
        let glass = ShelfSurface.washOpacities(solid: false)
        let solid = ShelfSurface.washOpacities(solid: true)
        #expect(glass == [0.22, 0.12, 0.18])
        #expect(solid.count == 3)
        for (soft, full) in zip(solid, glass) {
            #expect(abs(soft - full * ShelfSurface.softWashShare) < 0.0001)
        }
    }

    @Test("the solid ground of every theme is what its accent and text are checked on")
    func whenSolid_thenGroundIsTheCheckedGround() {
        for theme in AppTheme.allCases {
            for dark in [false, true] {
                let ground = theme.groundHex(dark: dark)
                #expect(ContrastRatio.between(theme.accentHex(dark: dark), ground) >= 4.5, "\(theme) \(dark)")
            }
        }
    }

    @Test("the setting is registered, and a backup restores a known surface and refuses an unknown one")
    func whenRestored_thenOnlyAKnownSurfaceIsApplied() throws {
        #expect(Setting.allNames.contains(Setting.shelfSurface.name))
        let defaults = ThrowawayDefaults.make()
        func restore(_ value: String) throws {
            let payload = ["version": 1, "settings": [Setting.shelfSurface.name: value]] as [String: Any]
            let data = try JSONSerialization.data(withJSONObject: payload)
            _ = try SettingsBackupManager.restore(from: data, into: defaults, notifying: NotificationCenter())
        }
        try restore("glass")
        #expect(defaults.string(forKey: Setting.shelfSurface.name) == "glass")
        try restore("frosted")
        #expect(defaults.string(forKey: Setting.shelfSurface.name) == "glass")
    }
}
