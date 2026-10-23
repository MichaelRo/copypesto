// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("SmartCollectionPredicate")
struct SmartCollectionPredicateTests {
    @Test("encodes and decodes a string-equals rule")
    func whenStringEqualsRule_thenRoundTrip() throws {
        let rule = PredicateRule(field: .type, op: .equals, value: .string("url"))
        let data = try SmartCollectionPredicate.encode(rule)
        let decoded = try SmartCollectionPredicate.decode(data)
        #expect(decoded == rule)
    }

    @Test("encodes and decodes a numeric olderThan rule")
    func whenNumericOlderThan_thenRoundTrip() throws {
        let rule = PredicateRule(field: .timestamp, op: .olderThanSeconds, value: .int(86_400))
        let data = try SmartCollectionPredicate.encode(rule)
        let decoded = try SmartCollectionPredicate.decode(data)
        #expect(decoded == rule)
    }

    @Test("encodes and decodes a boolean isPinned rule")
    func whenBoolIsPinned_thenRoundTrip() throws {
        let rule = PredicateRule(field: .isPinned, op: .isTrue, value: .none)
        let data = try SmartCollectionPredicate.encode(rule)
        let decoded = try SmartCollectionPredicate.decode(data)
        #expect(decoded == rule)
    }

    @Test("rejects timestamp + contains (operator not allowed for field)")
    func whenIncompatibleOp_thenValidationError() {
        let rule = PredicateRule(field: .timestamp, op: .contains, value: .string("foo"))
        #expect(throws: PredicateValidator.ValidationError.self) {
            try PredicateValidator.validate(rule)
        }
    }

    @Test("rejects isPinned + int value (value kind mismatch)")
    func whenValueKindMismatch_thenValidationError() {
        let rule = PredicateRule(field: .isPinned, op: .isTrue, value: .int(1))
        #expect(throws: PredicateValidator.ValidationError.self) {
            try PredicateValidator.validate(rule)
        }
    }

    @Test("canCompile returns true for supported version")
    func whenSupportedVersion_thenCompilable() {
        var rule = PredicateRule(field: .type, op: .equals, value: .string("url"))
        rule.version = 1
        #expect(SmartCollectionPredicate.canCompile(rule))
    }

    @Test("canCompile returns false for unknown future version")
    func whenUnknownVersion_thenNotCompilable() {
        var rule = PredicateRule(field: .type, op: .equals, value: .string("url"))
        rule.version = 99
        #expect(!SmartCollectionPredicate.canCompile(rule))
    }
}
