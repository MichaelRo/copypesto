// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("CollectionNaming")
struct CollectionNamingTests {
    @Test("a free name is kept as typed, apart from surrounding spaces")
    func whenFree_thenKept() {
        #expect(CollectionNaming.uniqueName("  Work ", existing: ["Home"]) == "Work")
    }

    @Test("a taken name gets the next number, like a folder in Finder")
    func whenTaken_thenNumbered() {
        #expect(CollectionNaming.uniqueName("Work", existing: ["Work"]) == "Work 2")
        #expect(CollectionNaming.uniqueName("Work", existing: ["Work", "Work 2"]) == "Work 3")
    }

    @Test("the number is the lowest free one")
    func whenGap_thenFillsIt() {
        #expect(CollectionNaming.uniqueName("Work", existing: ["Work", "Work 3"]) == "Work 2")
    }

    @Test("capitals and accents do not make two names different")
    func whenOnlyCaseDiffers_thenTaken() {
        #expect(CollectionNaming.uniqueName("work", existing: ["Work"]) == "work 2")
        #expect(CollectionNaming.uniqueName("Café", existing: ["Cafe"]) == "Café 2")
    }

    @Test("an empty name becomes New Collection, which is numbered when taken")
    func whenEmpty_thenDefault() {
        #expect(CollectionNaming.uniqueName("   ", existing: []) == "New Collection")
        #expect(CollectionNaming.uniqueName("", existing: ["New Collection"]) == "New Collection 2")
    }

    @Test("renaming a collection to its own name, or only changing its capitals, is not a clash")
    func whenRenamingToItself_thenUnchanged() {
        #expect(CollectionNaming.uniqueName("Work", existing: ["Work", "Home"], excluding: "Work") == "Work")
        #expect(CollectionNaming.uniqueName("WORK", existing: ["Work", "Home"], excluding: "Work") == "WORK")
        #expect(CollectionNaming.uniqueName("Home", existing: ["Work", "Home"], excluding: "Work") == "Home 2")
    }

    @Test("a copy is named after its source and numbered when the copy exists")
    func whenCopying_thenCopySuffix() {
        #expect(CollectionNaming.copyName(of: "Work", existing: ["Work"]) == "Work Copy")
        #expect(CollectionNaming.copyName(of: "Work", existing: ["Work", "Work Copy"]) == "Work Copy 2")
    }
}
