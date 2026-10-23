// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("NSFWMode")
struct NSFWModeTests {
    private func makeDefaults() -> UserDefaults {
        ThrowawayDefaults.make()
    }

    @Test("blur is the default")
    func whenNothingStored_thenBlur() {
        let store = makeDefaults()

        #expect(NSFWMode.current(from: store) == .blur)
    }

    @Test("each mode says what it does")
    func modesBehaviour() {
        #expect(NSFWMode.blur.detectsContent && NSFWMode.blur.blursCards && !NSFWMode.blur.hidesFromGrid)
        #expect(NSFWMode.hide.detectsContent && NSFWMode.hide.hidesFromGrid && NSFWMode.hide.blursCards)
        #expect(!NSFWMode.show.detectsContent && !NSFWMode.show.blursCards && !NSFWMode.show.hidesFromGrid)
    }

    @Test("a stored mode is read")
    func whenStored_thenRead() {
        let store = makeDefaults()
        store.set("hide", forKey: NSFWMode.defaultsKey)

        #expect(NSFWMode.current(from: store) == .hide)
    }

    @Test("an unknown stored value falls back to blur")
    func whenGarbage_thenBlur() {
        let store = makeDefaults()
        store.set("nonsense", forKey: NSFWMode.defaultsKey)

        #expect(NSFWMode.current(from: store) == .blur)
    }

    @Test("migration: a user who turned the old filter off gets show")
    func whenLegacyFilterOff_thenMigratesToShow() {
        let store = makeDefaults()
        store.set(false, forKey: "nsfwFilterEnabled")

        NSFWMode.migrateLegacySetting(in: store)

        #expect(NSFWMode.current(from: store) == .show)
    }

    @Test("migration: the old filter on (or never set) becomes blur")
    func whenLegacyFilterOn_thenMigratesToBlur() {
        let store = makeDefaults()
        store.set(true, forKey: "nsfwFilterEnabled")

        NSFWMode.migrateLegacySetting(in: store)

        #expect(NSFWMode.current(from: store) == .blur)
    }

    @Test("migration never overwrites a mode the user already chose")
    func whenModeAlreadyChosen_thenMigrationKeepsIt() {
        let store = makeDefaults()
        store.set("hide", forKey: NSFWMode.defaultsKey)
        store.set(false, forKey: "nsfwFilterEnabled")

        NSFWMode.migrateLegacySetting(in: store)

        #expect(NSFWMode.current(from: store) == .hide)
    }
}
