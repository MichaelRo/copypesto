// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Copying a snippet where there is no target app")
struct SnippetCopyPlanTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("text that is not a snippet, or has no placeholder, has no plan")
    func whenNotASnippet_thenNoPlan() {
        #expect(SnippetCopyPlan.plan(for: "Hello {{input:Name}}", isSnippet: false) == nil)
        #expect(SnippetCopyPlan.plan(for: "Hello there", isSnippet: true) == nil)
    }

    @Test("fields and the clipboard need the sheet; dates, times and IDs copy at once")
    func whenPlanned_thenTheSheetIsNeededOnlyForPeopleInput() throws {
        let asks = try #require(SnippetCopyPlan.plan(for: "Hi {{input:Name}}, {{date}}", isSnippet: true))
        #expect(asks.needsSheet)
        #expect(asks.fields.map(\.label) == ["Name"])

        let pastes = try #require(SnippetCopyPlan.plan(for: "Re: {{clipboard}}", isSnippet: true))
        #expect(pastes.needsSheet)
        #expect(pastes.usesClipboard)

        let automatic = try #require(SnippetCopyPlan.plan(for: "{{isodate}} {{uuid}} {{time}}", isSnippet: true))
        #expect(!automatic.needsSheet)
    }

    @Test("only app is named as left empty on iOS, while selection prompts and bare variables become inputs")
    func whenSelectionAppOrBareVariable_thenSelectionAndVariablePrompted() throws {
        let plan = try #require(SnippetCopyPlan.plan(
            for: "{{selection}} from {{app}} for {{company}} {{input:Who}}",
            isSnippet: true
        ))
        #expect(plan.usesSelection)
        #expect(plan.needsSheet)
        #expect(plan.leftEmpty == ["app"])
        #expect(plan.fields.map(\.label) == ["company", "Who"])
        var fills = SnippetFills()
        fills.values["company"] = "Acme"
        fills.values["Who"] = "Ana"
        #expect(
            plan.expanded(
                "{{selection}} from {{app}} for {{company}} {{input:Who}}",
                fills: fills,
                pastedClipboard: "",
                selectedText: "picked quote"
            ) == "picked quote from  for Acme Ana"
        )
    }

    @Test("expansion fills the fields, the date and the pasted clipboard, and never reads the live one")
    func whenExpanded_thenFilled() throws {
        let text = "Dear {{input:Name}}, re {{clipboard}} on {{isodate}}"
        let plan = try #require(SnippetCopyPlan.plan(for: text, isSnippet: true))
        var fills = SnippetFills.initial(for: plan.fields)
        fills.values["Name"] = "Ana"

        let result = plan.expanded(text, fills: fills, pastedClipboard: "invoice 12", at: date)
        #expect(result.hasPrefix("Dear Ana, re invoice 12 on 20"))

        let none = plan.expanded(text, fills: fills, pastedClipboard: "", at: date)
        #expect(none.hasPrefix("Dear Ana, re  on 20"))
    }

    @Test("a choice and an optional section follow the fills")
    func whenChoiceAndOptional_thenTheyFollowTheFills() throws {
        let text = "{{choice:Tone options=\"Warm|Formal\"}}{{optional:Sign}} Bye{{/optional}}"
        let plan = try #require(SnippetCopyPlan.plan(for: text, isSnippet: true))
        var fills = SnippetFills.initial(for: plan.fields)
        #expect(plan.expanded(text, fills: fills, pastedClipboard: "") == "Warm")
        fills.values["Tone"] = "Formal"
        fills.included.insert("Sign")
        #expect(plan.expanded(text, fills: fills, pastedClipboard: "") == "Formal Bye")
    }
}
