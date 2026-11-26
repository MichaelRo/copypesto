// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Card meta line")
struct CardMetaLineTests {
    private let measure = ["149 characters \u{00B7} 5 lines", "149 characters"]

    @Test("at rest the line names the app and the age, and gives up the app's name before the age")
    func whenAtRest_thenAppAndAge() {
        let lines = CardMetaLine.candidates(.init(source: "Xcode", age: "4m ago", measure: measure))
        #expect(lines == ["Xcode \u{00B7} 4m ago", "4m ago"])
    }

    @Test("at rest the size is not stated: it joins on the card being looked at")
    func whenAtRest_thenNoSize() {
        let lines = CardMetaLine.candidates(.init(source: "Xcode", age: "4m ago", measure: measure))
        #expect(lines.allSatisfy { !$0.contains("characters") })
    }

    @Test("a focused or pointed card adds the size, fullest first, and falls back to the app and age")
    func whenActive_thenSizeJoins() {
        let lines = CardMetaLine.candidates(.init(source: "Xcode", age: "4m ago", measure: measure, isActive: true))
        #expect(lines == [
            "Xcode \u{00B7} 4m ago \u{00B7} 149 characters \u{00B7} 5 lines",
            "Xcode \u{00B7} 4m ago \u{00B7} 149 characters",
            "Xcode \u{00B7} 4m ago",
            "4m ago"
        ])
    }

    @Test("a focused picture keeps its dimensions over the app's name, whose icon stays on the line (ADR 0080)")
    func whenPictureActive_thenDimensionsOutlastTheAppName() {
        let lines = CardMetaLine.candidates(.init(
            source: "Preview", age: "4m ago", measure: ["1920 \u{00D7} 1080"], isActive: true,
            measureOutlastsSource: true
        ))
        #expect(lines == [
            "Preview \u{00B7} 4m ago \u{00B7} 1920 \u{00D7} 1080",
            "4m ago \u{00B7} 1920 \u{00D7} 1080",
            "Preview \u{00B7} 4m ago",
            "4m ago"
        ])
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
            .init(age: "7m ago", measure: ["2 characters"], showsWholeClip: true, isActive: true)
        )
        #expect(lines == ["7m ago"])
    }

    @Test("an app macOS could not name leaves the age alone")
    func whenNoSource_thenAgeOnly() {
        #expect(CardMetaLine.candidates(.init(age: "just now")) == ["just now"])
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
        let lines = CardMetaLine.candidates(.init(age: "1h ago", measure: ["1.2 MB"], isActive: true))
        #expect(Set(lines).count == lines.count)
    }

    @Test("when the title sits on the card face, the foot line keeps the source app and age")
    func whenTitleShownOnFace_thenSourceStaysLead() {
        let rest = CardMetaLine.candidates(
            .init(
                title: "API Key Docs",
                source: "Xcode",
                age: "4m ago",
                measure: measure,
                showsTitleOnFace: true
            )
        )
        #expect(rest == ["Xcode \u{00B7} 4m ago", "4m ago"])

        let active = CardMetaLine.candidates(
            .init(
                title: "API Key Docs",
                source: "Xcode",
                age: "4m ago",
                measure: measure,
                isActive: true,
                showsTitleOnFace: true
            )
        )
        #expect(active == [
            "Xcode \u{00B7} 4m ago \u{00B7} 149 characters \u{00B7} 5 lines",
            "Xcode \u{00B7} 4m ago \u{00B7} 149 characters",
            "Xcode \u{00B7} 4m ago",
            "4m ago"
        ])
    }

    @Test("when the title sits on the card face and no source app is known, only the age remains")
    func whenTitleShownOnFaceAndNoSource_thenAgeOnly() {
        let lines = CardMetaLine.candidates(
            .init(title: "Scratch", source: nil, age: "2d ago", showsTitleOnFace: true)
        )
        #expect(lines == ["2d ago"])
    }
}
