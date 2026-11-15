// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The AutoFill picker's list")
struct QuickInsertMenuTests {
    private func entry(_ text: String, _ section: QuickInsertEntry.Section, title: String? = nil) -> QuickInsertEntry {
        QuickInsertEntry(
            id: UUID(), section: section, kind: .text, title: title ?? text, text: text,
            expandsOnInsert: section == .snippets
        )
    }

    private var set: QuickInsertSet {
        QuickInsertSet(createdAt: .now, entries: [
            entry("12 Basil Lane", .pinned, title: "Home"),
            entry("Thanks, {{date}}", .snippets),
            entry("Basil pesto recipe", .recent),
            entry("tracking 1Z999", .recent)
        ])
    }

    @Test("no set, or one that would not open, is unavailable; an empty set is empty; otherwise ready")
    func whenLoaded_thenTheStateSaysWhatThereIs() {
        #expect(QuickInsertMenu(set: nil).state == .unavailable)
        #expect(QuickInsertMenu(set: .empty).state == .empty)
        #expect(QuickInsertMenu(set: set).state == .ready)
    }

    @Test("the sections come Pinned, Snippets, Recent, and an empty one is not shown")
    func whenGrouped_thenSectionsAreInOrder() {
        #expect(QuickInsertMenu(set: set).groups(matching: "").map(\.section) == [.pinned, .snippets, .recent])
        let noSnippets = QuickInsertSet(createdAt: .now, entries: set.entries.filter { $0.section != .snippets })
        #expect(QuickInsertMenu(set: noSnippets).groups(matching: "").map(\.section) == [.pinned, .recent])
    }

    @Test("a search matches the title or the text, ignoring case and accents, and keeps the sections")
    func whenSearched_thenOnlyMatchesRemain() {
        let menu = QuickInsertMenu(set: set)

        #expect(menu.groups(matching: "basil").map(\.section) == [.pinned, .recent])
        #expect(menu.groups(matching: "  HOME ").flatMap(\.entries).map(\.text) == ["12 Basil Lane"])
        #expect(menu.groups(matching: "pésto").flatMap(\.entries).map(\.text) == ["Basil pesto recipe"])
        #expect(menu.groups(matching: "nothing like this").isEmpty)
    }

    @Test("a snippet inserts with its fills expanded and its caret marker gone; any other clip as it is")
    func whenInserted_thenSnippetsExpand() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let snippet = entry("Due {{isodate}}{{cursor}}.", .snippets)
        let plain = entry("Due {{isodate}}", .recent)

        let expanded = snippet.insertionText(at: date)
        #expect(!expanded.contains("{{"))
        #expect(expanded.hasPrefix("Due 20"))
        #expect(expanded.hasSuffix("."))
        #expect(plain.insertionText(at: date) == "Due {{isodate}}")
    }
}
