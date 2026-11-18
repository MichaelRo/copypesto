// SPDX-License-Identifier: MIT
import PestoCore
import Testing
@testable import Pesto

/// The yes/no condition was worded for pinning whatever the field: "From Another Device is pinned".
@Suite("Smart collection rules read as what they test")
struct SmartRuleWordingTests {
    @Test("the device rule says where the clip came from, not that it is pinned")
    func whenTheFieldIsFromAnotherDevice_thenTheConditionNamesTheDevice() {
        #expect(PredicateRule.Operator.isTrue.displayName(for: .isRemote) == "came from another device")
        #expect(PredicateRule.Operator.isFalse.displayName(for: .isRemote) == "was copied on this Mac")
    }

    @Test("the pinned rule and the other conditions keep their words")
    func whenTheFieldIsPinned_thenTheConditionSaysPinned() {
        #expect(PredicateRule.Operator.isTrue.displayName(for: .isPinned) == "is pinned")
        #expect(PredicateRule.Operator.isFalse.displayName(for: .isPinned) == "is not pinned")
        #expect(PredicateRule.Operator.contains.displayName(for: .previewText) == "contains")
    }
}
