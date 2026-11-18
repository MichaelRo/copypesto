// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("A snippet is filled in before it is copied, and a text clip can become one")
@MainActor
struct MobileSnippetTests {
    private func snippet(_ library: MobileTestLibrary, _ text: String) async throws -> ClipboardItem {
        let item = try await library.add(text)
        _ = try await library.service.togglePinned(id: item.id)
        try await library.refreshed()
        return try #require(library.store.item(for: item.id))
    }

    @Test("a snippet with a field asks first and copies nothing until the sheet answers")
    func whenSnippetAsks_thenTheSheetIsRequested() async throws {
        let library = try await MobileTestLibrary()
        let item = try await snippet(library, "Dear {{input:Name}}, today is {{isodate}}")

        #expect(!library.state.copy(item))
        let request = try #require(library.state.pendingFill)
        #expect(request.id == item.id)
        #expect(request.plan.fields.map(\.label) == ["Name"])

        var fills = request.initial
        fills.values["Name"] = "Ana"
        #expect(library.state.copyFilled(request, fills: fills, pastedClipboard: ""))
        let copied = try #require(AppPasteboard.general.string)
        #expect(copied.hasPrefix("Dear Ana, today is 20"))
        #expect(library.state.pendingFill == nil)
    }

    @Test("a snippet of dates and IDs copies at once, expanded")
    func whenSnippetFillsItself_thenItCopiesAtOnce() async throws {
        let library = try await MobileTestLibrary()
        let item = try await snippet(library, "Ref {{isodate}}")

        #expect(library.state.copy(item))
        #expect(library.state.pendingFill == nil)
        #expect(try #require(AppPasteboard.general.string).hasPrefix("Ref 20"))
    }

    @Test("an unpinned clip with braces is plain text and copies as it is")
    func whenNotPinned_thenItIsNotASnippet() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("{{input:Name}}")

        #expect(library.state.copy(item))
        #expect(AppPasteboard.general.string == "{{input:Name}}")
    }

    @Test("the clipboard placeholder is filled from what the sheet pasted, not from the clipboard")
    func whenClipboardPlaceholder_thenOnlyThePastedTextIsUsed() async throws {
        let library = try await MobileTestLibrary()
        let item = try await snippet(library, "Re: {{clipboard}}")
        AppPasteboard.general.string = "secret on the board"

        #expect(!library.state.copy(item))
        let request = try #require(library.state.pendingFill)
        #expect(request.plan.usesClipboard)
        library.state.copyFilled(request, fills: request.initial, pastedClipboard: "invoice 7")
        #expect(AppPasteboard.general.string == "Re: invoice 7")
    }

    @Test("a filled-in value is remembered for next time, and a secret-looking one is not")
    func whenCopiedFilled_thenTheValuesAreRemembered() async throws {
        let library = try await MobileTestLibrary()
        let item = try await snippet(library, "Hi {{input:Name}} {{input:Key}}")
        #expect(!library.state.copy(item))
        let request = try #require(library.state.pendingFill)
        var fills = request.initial
        fills.values["Name"] = "Ana"
        fills.values["Key"] = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"
        library.state.copyFilled(request, fills: fills, pastedClipboard: "")
        await library.service.waitForBackgroundWork()
        try await Task.sleep(for: .milliseconds(300))
        try await library.refreshed()

        let again = try #require(library.store.item(for: item.id))
        #expect(again.metadata.fieldMemory?["Name"] == "Ana")
        #expect(again.metadata.fieldMemory?["Key"] == nil)
        #expect(!library.state.copy(again))
        #expect(library.state.pendingFill?.initial.values["Name"] == "Ana")
    }

    @Test("Save as Snippet pins the text, turns {name} into a fill-in, and is offered only for plain text clips")
    func whenSavedAsSnippet_thenItIsPinnedWithFillIns() async throws {
        let library = try await MobileTestLibrary()
        let item = try await library.add("Hello {Name}, welcome")
        #expect(library.state.canSaveAsSnippet(item))

        await library.state.saveAsSnippet(item)
        try await library.refreshed()

        let saved = try #require(library.store.items.first { $0.isTemplate })
        #expect(saved.isPinned)
        #expect(ClipContent.of(saved)?.plainText?.contains("{{") == true)
        #expect(!library.state.canSaveAsSnippet(saved))
    }
}
