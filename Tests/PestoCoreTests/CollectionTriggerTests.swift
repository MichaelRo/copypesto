// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Collection trigger")
struct CollectionTriggerTests {
    private func board(_ name: String, trigger: String? = nil) -> Pinboard {
        Pinboard(name: name, symbolName: "tray", colorHex: "#2F7A49", sortOrder: 0, triggerBundleID: trigger)
    }

    @Test("an app opens the shelf on the collection set for it")
    func whenAnAppHasACollection_thenThatCollectionOpens() {
        let work = board("Work")
        let mail = board("Mail", trigger: "com.apple.mail")
        #expect(CollectionTrigger.collectionID(for: "com.apple.mail", in: [work, mail]) == mail.id)
    }

    @Test("an app with no collection of its own opens the shelf on All")
    func whenNoCollectionIsSetForTheApp_thenAllOpens() {
        let mail = board("Mail", trigger: "com.apple.mail")
        #expect(CollectionTrigger.collectionID(for: "com.apple.Safari", in: [mail]) == nil)
    }

    @Test("no bundle identifier never opens a collection, though most collections have no trigger")
    func whenThereIsNoBundleIdentifier_thenNoCollectionMatchesTheEmptyTriggers() {
        let boards = [board("Work"), board("Recipes"), board("Mail", trigger: "com.apple.mail")]
        #expect(CollectionTrigger.collectionID(for: nil, in: boards) == nil)
        #expect(CollectionTrigger.collectionID(for: "", in: boards) == nil)
    }
}
