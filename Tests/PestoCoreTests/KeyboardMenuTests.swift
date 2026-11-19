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
        #expect(menu.groups.isEmpty)
    }

    @Test("with Full Access: no set is unavailable, an empty set is empty, otherwise ready")
    func whenFullAccess_thenTheStateSaysWhatThereIs() {
        #expect(KeyboardMenu(hasFullAccess: true) { nil }.state == .unavailable)
        #expect(KeyboardMenu(hasFullAccess: true) { .empty }.state == .empty)
        #expect(KeyboardMenu(hasFullAccess: true) { full }.state == .ready)
    }

    @Test("one list: Pinned, then Snippets, then Recent, and a section with no clip is left out")
    func whenReady_thenOneListInSectionOrder() {
        let menu = KeyboardMenu(hasFullAccess: true) { full }
        #expect(menu.groups.map(\.section) == [.pinned, .snippets, .recent])
        #expect(menu.groups.last?.entries.map(\.text) == ["Basil pesto recipe", "tracking 1Z999"])
        let noSnippets = QuickInsertSet(createdAt: .now, entries: full.entries.filter { $0.section != .snippets })
        #expect(KeyboardMenu(hasFullAccess: true) { noSnippets }.groups.map(\.section) == [.pinned, .recent])
    }
}
