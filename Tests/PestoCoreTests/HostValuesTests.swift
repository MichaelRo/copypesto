// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("HostValues")
struct HostValuesTests {
    @Test("the shelf and the floating window each keep their own value")
    func whenOneHostSets_thenTheOtherIsUntouched() {
        var chips = HostValues<[String]>([])
        chips[.shelf] = ["a", "b"]
        chips[.pinnedWindow] = ["b", "a"]

        #expect(chips[.shelf] == ["a", "b"])
        #expect(chips[.pinnedWindow] == ["b", "a"])
    }

    @Test("both hosts start with the initial value")
    func whenNew_thenBothHaveTheInitialValue() {
        let chips = HostValues(7)

        #expect(chips[.shelf] == 7)
        #expect(chips[.pinnedWindow] == 7)
    }
}
