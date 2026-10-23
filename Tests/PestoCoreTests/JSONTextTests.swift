// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("JSON text is tagged so it can be found")
struct JSONTextTests {
    @Test("an object or an array that parses is code in the json language")
    func whenValidJSON_thenCodeJSON() {
        let result = ContentClassifier.classify(text: "{\"recipe\": \"pesto\", \"servings\": 4}")
        #expect(result.type == .code)
        #expect(result.detectedLanguage == "json")
        #expect(ContentClassifier.classify(text: "[1, 2, 3]").detectedLanguage == "json")
    }

    @Test("text that only looks like JSON, or is empty, is not", arguments: [
        "{not json}", "[just a note]", "{}", "[]", "{\"open\": "
    ])
    func whenNotJSON_thenNot(text: String) {
        #expect(ContentClassifier.classify(text: text).detectedLanguage != "json")
    }
}
