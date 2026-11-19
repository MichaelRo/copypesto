// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The keyboard's menu")
struct KeyboardMenuTests {
    private func entry(_ text: String, _ section: QuickInsertEntry.Section) -> QuickInsertEntry {
        QuickInsertEntry(
            id: UUID(), section: section, kind: .text, title: text, text: text,
            expandsOnInsert: section == .snippets
        )
    }

    private var full: QuickInsertSet {
        QuickInsertSet(createdAt: .now, entries: [
            entry("Basil pesto recipe", .recent),
            entry("12 Basil Lane", .pinned),
            entry("Thanks, {{date}}", .snippets),
            entry("tracking 1Z999", .recent)
        ])
    }

    @Test("without Full Access the menu is restricted and never asks for the set")
    func whenNoFullAccess_thenRestrictedWithoutReading() {
        var reads = 0
        let menu = KeyboardMenu(hasFullAccess: false) {
            reads += 1
            return full
        }
        #expect(menu.state == .restricted)
        #expect(reads == 0)
        #expect(menu.filters.isEmpty)
        #expect(menu.entries(for: .all).isEmpty)
    }

    @Test("with Full Access: no set is unavailable, an empty set is empty, otherwise ready")
    func whenFullAccess_thenTheStateSaysWhatThereIs() {
        #expect(KeyboardMenu(hasFullAccess: true) { nil }.state == .unavailable)
        #expect(KeyboardMenu(hasFullAccess: true) { .empty }.state == .empty)
        #expect(KeyboardMenu(hasFullAccess: true) { full }.state == .ready)
    }

    @Test("the starters are offered in every state")
    func whenAnyState_thenStartersAreThere() {
        for menu in [
            KeyboardMenu(hasFullAccess: false) { full }, KeyboardMenu(hasFullAccess: true) { nil },
            KeyboardMenu(hasFullAccess: true) { .empty }, KeyboardMenu(hasFullAccess: true) { full }
        ] {
            #expect(menu.starters == KeyboardStarter.allCases)
        }
    }

    @Test("All lists Pinned, then Snippets, then Recent; a section filter lists only its own")
    func whenFiltered_thenSectionsInOrder() {
        let menu = KeyboardMenu(hasFullAccess: true) { full }
        #expect(menu.entries(for: .all).map(\.section) == [.pinned, .snippets, .recent, .recent])
        #expect(menu.entries(for: .recent).map(\.text) == ["Basil pesto recipe", "tracking 1Z999"])
        #expect(menu.entries(for: .pinned).map(\.text) == ["12 Basil Lane"])
    }

    @Test("a filter for an empty section is not offered")
    func whenASectionIsEmpty_thenItsFilterIsHidden() {
        let menu = KeyboardMenu(hasFullAccess: true) { full }
        #expect(menu.filters == [.all, .pinned, .snippets, .recent])
        let noSnippets = QuickInsertSet(createdAt: .now, entries: full.entries.filter { $0.section != .snippets })
        #expect(KeyboardMenu(hasFullAccess: true) { noSnippets }.filters == [.all, .pinned, .recent])
    }

    @Test("with one section there is nothing to choose, so no filters show")
    func whenOneSection_thenNoFilters() {
        let onlyRecent = QuickInsertSet(createdAt: .now, entries: full.entries.filter { $0.section == .recent })
        let menu = KeyboardMenu(hasFullAccess: true) { onlyRecent }
        #expect(menu.filters.isEmpty)
        #expect(menu.entries(for: .all).count == 2)
    }

    @Test("each filter has a title")
    func whenTitled_thenNotEmpty() {
        #expect(KeyboardMenu.Filter.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
