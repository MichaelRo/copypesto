// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Korean letters typed one jamo at a time join into syllables")
struct HangulComposerTests {
    private func typed(_ jamo: [String]) -> String {
        jamo.reduce(into: "") { text, next in text = HangulComposer.appending(next, to: text) }
    }

    @Test("an initial, a vowel and a final make one syllable, and the next syllable follows")
    func whenTyped_thenSyllablesForm() {
        #expect(typed(["ㅎ", "ㅏ", "ㄴ"]) == "한")
        #expect(typed(["ㅎ", "ㅏ", "ㄴ", "ㄱ", "ㅡ", "ㄹ"]) == "한글")
        #expect(typed(["ㄱ"]) == "ㄱ")
        #expect(typed(["ㅏ"]) == "ㅏ")
    }

    @Test("a final consonant moves to the next syllable when a vowel follows it")
    func whenVowelAfterFinal_thenTheFinalMoves() {
        #expect(typed(["ㄷ", "ㅏ", "ㄹ", "ㄱ"]) == "닭")
        #expect(typed(["ㄷ", "ㅏ", "ㄹ", "ㄱ", "ㅏ"]) == "달가")
        #expect(typed(["ㅎ", "ㅏ", "ㄴ", "ㅏ"]) == "하나")
    }

    @Test("two vowels join where Korean allows it")
    func whenCompoundVowel_thenItJoins() {
        #expect(typed(["ㄱ", "ㅗ", "ㅏ"]) == "과")
        #expect(typed(["ㅇ", "ㅜ", "ㅓ"]) == "워")
        #expect(typed(["ㄱ", "ㅏ", "ㅏ"]) == "가ㅏ")
    }

    @Test("Delete takes back the last jamo, not the whole syllable")
    func whenDeleting_thenOneJamoGoes() {
        #expect(HangulComposer.deletingLast(from: "한") == "하")
        #expect(HangulComposer.deletingLast(from: "하") == "ㅎ")
        #expect(HangulComposer.deletingLast(from: "닭") == "달")
        #expect(HangulComposer.deletingLast(from: "과") == "고")
        #expect(HangulComposer.deletingLast(from: "ab") == "a")
        #expect(HangulComposer.deletingLast(from: "").isEmpty)
    }

    @Test("anything that is not a jamo is simply added")
    func whenNotJamo_thenAppended() {
        #expect(HangulComposer.appending(" ", to: "한") == "한 ")
        #expect(HangulComposer.appending("a", to: "한") == "한a")
        #expect(HangulComposer.appending("ㅏ", to: "x") == "xㅏ")
    }

    @Test("the query composes Korean and stays within its limit")
    func whenQueryComposes_thenBounded() {
        var query = KeyboardQuery()
        for jamo in ["ㅎ", "ㅏ", "ㄴ"] {
            query.type(jamo, composingHangul: true)
        }
        #expect(query.text == "한")
        query.deleteBackward(decomposingHangul: true)
        #expect(query.text == "하")
        query.deleteBackward()
        #expect(query.text.isEmpty)
    }
}
