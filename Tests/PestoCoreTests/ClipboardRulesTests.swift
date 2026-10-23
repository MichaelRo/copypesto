// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("ClipboardRules")
struct ClipboardRulesTests {
    @Test("utm parameters are stripped and other parameters kept")
    func whenTrackingParams_thenStripped() {
        let rules = ClipboardRules(stripTrackingParameters: true)

        #expect(rules.apply(to: "https://example.com/a?utm_source=x&id=7") == "https://example.com/a?id=7")
    }

    @Test("a GitHub ref parameter is meaningful and survives")
    func whenRefParameter_thenKept() {
        let rules = ClipboardRules(stripTrackingParameters: true)
        let url = "https://github.com/o/r/blob/x/file.swift?ref=main"

        #expect(rules.apply(to: url) == url)
    }

    @Test("a URL with no tracking parameter is returned byte for byte, encoded characters included")
    func whenNoTrackingParams_thenEncodingUntouched() {
        let rules = ClipboardRules(stripTrackingParameters: true)
        let urls = [
            "https://example.com/search?q=c%2B%2B",
            "https://bucket.s3.amazonaws.com/f?X-Amz-Signature=ab%2Fcd%2Bef&X-Amz-Expires=60",
            "https://example.com/?a=1&a=2&empty="
        ]

        for url in urls {
            #expect(rules.apply(to: url) == url)
        }
    }

    @Test("stripping a tracking parameter keeps the encoding of the parameters that stay")
    func whenStrippingOne_thenOthersKeepEncoding() {
        let rules = ClipboardRules(stripTrackingParameters: true)

        #expect(
            rules.apply(to: "https://example.com/s?utm_source=x&q=c%2B%2B")
                == "https://example.com/s?q=c%2B%2B"
        )
    }

    @Test("with the rule off nothing is stripped")
    func whenRuleOff_thenUntouched() {
        let rules = ClipboardRules(stripTrackingParameters: false)
        let url = "https://example.com/?utm_source=x"

        #expect(rules.apply(to: url) == url)
    }

    @Test("rules follow the defaults store when it changes, with the documented defaults")
    func whenDefaultsChange_thenFromDefaultsReflectsThem() {
        let store = ThrowawayDefaults.make()

        #expect(ClipboardRules.from(store).stripTrackingParameters)
        store.set(false, forKey: "ruleStripTracking")
        store.set(true, forKey: "ruleTrimWhitespace")

        let rules = ClipboardRules.from(store)
        #expect(!rules.stripTrackingParameters)
        #expect(rules.trimWhitespace)
    }
}
