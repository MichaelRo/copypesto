// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("PredicateBuilder + PredicateValidator")
struct PredicateBuilderTests {
    // MARK: - Allowed operators per field

    @Test("string-equality fields accept equals and notEquals")
    func whenStringEqualityField_thenEqualsAndNotEqualsAllowed() {
        for field in [PredicateRule.Field.type, .sourceBundleID, .sensitivity, .detectedLanguage] {
            let allowed = PredicateValidator.allowedOperators(for: field)
            #expect(allowed.contains(.equals))
            #expect(allowed.contains(.notEquals))
            #expect(!allowed.contains(.contains))
            #expect(!allowed.contains(.olderThanSeconds))
            #expect(!allowed.contains(.isTrue))
        }
    }

    @Test("text-search fields accept contains, beginsWith, endsWith")
    func whenTextSearchField_thenAllStringOpsAllowed() {
        for field in [PredicateRule.Field.sourceAppName, .previewText] {
            let allowed = PredicateValidator.allowedOperators(for: field)
            #expect(allowed.contains(.equals))
            #expect(allowed.contains(.notEquals))
            #expect(allowed.contains(.contains))
            #expect(allowed.contains(.beginsWith))
            #expect(allowed.contains(.endsWith))
        }
    }

    @Test("timestamp field only accepts time operators")
    func whenTimestampField_thenOnlyTimeOpsAllowed() {
        let allowed = PredicateValidator.allowedOperators(for: .timestamp)
        #expect(allowed == [.olderThanSeconds, .newerThanSeconds])
    }

    @Test("isPinned field only accepts isTrue and isFalse")
    func whenIsPinnedField_thenOnlyBoolOpsAllowed() {
        let allowed = PredicateValidator.allowedOperators(for: .isPinned)
        #expect(allowed == [.isTrue, .isFalse])
    }

    @Test("isRemote field only accepts isTrue and isFalse")
    func whenIsRemoteField_thenOnlyBoolOpsAllowed() {
        #expect(PredicateValidator.allowedOperators(for: .isRemote) == [.isTrue, .isFalse])
    }

    // MARK: - Value kind matching

    @Test("string operators require string value")
    func whenStringOp_thenStringValueRequired() throws {
        for op in [PredicateRule.Operator.equals, .notEquals, .contains, .beginsWith, .endsWith] {
            let rule = PredicateRule(field: .previewText, op: op, value: .string("x"))
            #expect(throws: Never.self) { try PredicateValidator.validate(rule) }
        }
    }

    @Test("time operators require int value")
    func whenTimeOp_thenIntValueRequired() throws {
        let rule = PredicateRule(field: .timestamp, op: .olderThanSeconds, value: .int(3600))
        #expect(throws: Never.self) { try PredicateValidator.validate(rule) }
    }

    @Test("bool operators require none value")
    func whenBoolOp_thenNoneValueRequired() throws {
        let rule = PredicateRule(field: .isPinned, op: .isTrue, value: .none)
        #expect(throws: Never.self) { try PredicateValidator.validate(rule) }
    }

    @Test("string op with int value throws valueKindMismatch")
    func whenStringOpIntValue_thenValueKindMismatch() {
        let rule = PredicateRule(field: .previewText, op: .contains, value: .int(42))
        #expect(throws: PredicateValidator.ValidationError.valueKindMismatch(expected: "string", got: "int")) {
            try PredicateValidator.validate(rule)
        }
    }

    @Test("time op with string value throws valueKindMismatch")
    func whenTimeOpStringValue_thenValueKindMismatch() {
        let rule = PredicateRule(field: .timestamp, op: .olderThanSeconds, value: .string("not an int"))
        #expect(throws: PredicateValidator.ValidationError.valueKindMismatch(expected: "int", got: "string")) {
            try PredicateValidator.validate(rule)
        }
    }

    @Test("incompatible field+op throws operatorNotAllowedForField")
    func whenIncompatibleFieldOp_thenOperatorNotAllowed() {
        let rule = PredicateRule(field: .type, op: .contains, value: .string("x"))
        #expect(throws: PredicateValidator.ValidationError.operatorNotAllowedForField(.type, .contains)) {
            try PredicateValidator.validate(rule)
        }
    }

    // MARK: - PredicateRule value accessors

    @Test("stringValue returns value for string case, nil otherwise")
    func stringValueAccessor() {
        #expect(PredicateRule.Value.string("hi").stringValue == "hi")
        #expect(PredicateRule.Value.int(1).stringValue == nil)
        #expect(PredicateRule.Value.bool(true).stringValue == nil)
        #expect(PredicateRule.Value.none.stringValue == nil)
    }

    @Test("intValue returns value for int case, nil otherwise")
    func intValueAccessor() {
        #expect(PredicateRule.Value.int(42).intValue == 42)
        #expect(PredicateRule.Value.string("x").intValue == nil)
        #expect(PredicateRule.Value.none.intValue == nil)
    }

    @Test("boolValue returns value for bool case, nil otherwise")
    func boolValueAccessor() {
        #expect(PredicateRule.Value.bool(true).boolValue == true)
        #expect(PredicateRule.Value.bool(false).boolValue == false)
        #expect(PredicateRule.Value.none.boolValue == nil)
    }

    // MARK: - PredicateRule default version

    @Test("default version is 1")
    func defaultVersionIsOne() {
        let rule = PredicateRule(field: .type, op: .equals, value: .string("text"))
        #expect(rule.version == 1)
    }

    // MARK: - CaseIterable coverage (regression guard)

    @Test("all Fields have at least one allowed operator")
    func allFieldsHaveAllowedOperators() {
        for field in PredicateRule.Field.allCases {
            let allowed = PredicateValidator.allowedOperators(for: field)
            #expect(!allowed.isEmpty, "Field \(field) has no allowed operators")
        }
    }

    @Test("a rule set holding a rule that cannot be evaluated is refused when it is saved")
    func whenARuleSetHasAnInvalidRule_thenEncodingThrows() {
        let invalid = PredicateRule(field: .isPinned, op: .contains, value: .string("x"))
        let ruleSet = PredicateRuleSet(combinator: .and, groups: [.init(combinator: .and, rules: [invalid])])

        #expect(throws: PredicateValidator.ValidationError.self) { try SmartCollectionPredicate.encodeRuleSet(ruleSet) }
    }

    @Test("a damaged v2 rule set reports its own problem, not the v1 decoder's")
    func whenAV2BlobIsDamaged_thenTheV2ErrorIsReported() {
        let damaged = Data(#"{"schemaVersion":2,"combinator":"and","groups":[{"combinator":"and"}]}"#.utf8)

        do {
            _ = try SmartCollectionPredicate.decodeRuleSet(damaged)
            Issue.record("a damaged rule set decoded")
        } catch let error as DecodingError {
            #expect("\(error)".contains("rules"), "the error should name the missing rules: \(error)")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
