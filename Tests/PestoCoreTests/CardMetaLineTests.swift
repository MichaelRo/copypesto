// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Card meta line")
struct CardMetaLineTests {
    private let measure = ["149 characters \u{00B7} 5 lines", "149 characters"]

    @Test("at rest the line is the age and the size, and gives up the size before the age")
    func whenAtRest_thenAgeAndSize() {
        let lines = CardMetaLine.candidates(.init(source: "Xcode", age: "4m ago", measure: measure))
        #expect(lines == [
            "4m ago \u{00B7} 149 characters \u{00B7} 5 lines",
            "4m ago \u{00B7} 149 characters",
            "4m ago"
        ])
    }

    @Test("at rest the app is never named: its icon says it")
    func whenAtRest_thenNoAppName() {
        let lines = CardMetaLine.candidates(.init(source: "Xcode", age: "4m ago", measure: measure))
        #expect(lines.allSatisfy { !$0.contains("Xcode") })
    }

    @Test("a focused or pointed card leads with the app's name and falls back to the age alone")
    func whenActive_thenAppNameLeads() {
        let lines = CardMetaLine.candidates(.init(source: "Xcode", age: "4m ago", measure: measure, isActive: true))
        #expect(lines.first == "Xcode \u{00B7} 4m ago \u{00B7} 149 characters \u{00B7} 5 lines")
        #expect(lines.contains("Xcode \u{00B7} 4m ago"))
        #expect(lines.last == "4m ago")
    }

    @Test("a title the person gave always leads, at rest too, and is the last thing given up")
    func whenTitled_thenTitleAlwaysShown() {
        let rest = CardMetaLine.candidates(.init(title: "Thank you", source: "Notes", age: "2d ago", measure: measure))
        #expect(rest.allSatisfy { $0.hasPrefix("Thank you") })
        #expect(rest.last == "Thank you")
        let active = CardMetaLine.candidates(
            .init(title: "Thank you", source: "Notes", age: "2d ago", isActive: true)
        )
        #expect(active == ["Thank you \u{00B7} 2d ago", "Thank you"])
    }

    @Test("a card that shows the whole of a short text does not count it")
    func whenWholeClipShown_thenNoSize() {
        let lines = CardMetaLine.candidates(
            .init(age: "7m ago", measure: ["2 characters"], showsWholeClip: true)
        )
        #expect(lines == ["7m ago"])
    }

    @Test("an app macOS could not name leaves the age alone on a focused card")
    func whenNoSource_thenAgeOnly() {
        #expect(CardMetaLine.candidates(.init(age: "just now", isActive: true)) == ["just now"])
    }

    @Test("the pin is drawn only when nothing else already says the clip is kept")
    func whenSnippetOrShortcut_thenNoPin() {
        #expect(CardMetaLine.showsPin(isPinned: true, isSnippet: false, hasShortcut: false))
        #expect(!CardMetaLine.showsPin(isPinned: true, isSnippet: true, hasShortcut: false))
        #expect(!CardMetaLine.showsPin(isPinned: true, isSnippet: false, hasShortcut: true))
        #expect(!CardMetaLine.showsPin(isPinned: false, isSnippet: false, hasShortcut: false))
    }

    @Test("no wording is offered twice")
    func whenCandidates_thenDistinct() {
        let lines = CardMetaLine.candidates(.init(age: "1h ago", measure: ["1.2 MB"]))
        #expect(Set(lines).count == lines.count)
    }
}
