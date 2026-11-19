// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The keyboard's menu")
struct KeyboardMenuTests {
    private let work = UUID()

    private func entry(_ text: String, _ section: QuickInsertEntry.Section, title: String? = nil) -> QuickInsertEntry {
        QuickInsertEntry(
            id: UUID(), section: section, kind: .text, title: title ?? text, text: text,
            expandsOnInsert: section == .snippets
        )
    }

    private func full() -> QuickInsertSet {
        let standup = entry("Standup at 10", .collection)
        let home = entry("12 Basil Lane", .pinned, title: "Home address")
        return QuickInsertSet(
            createdAt: .now,
            entries: [
                home, entry("Thanks, {{date}}", .snippets), entry("Basil pesto recipe", .recent),
                entry("tracking 1Z999", .recent), standup
            ],
            collections: [
                QuickInsertCollection(id: work, name: "Work", symbolName: "briefcase", entryIDs: [standup.id, home.id])
            ],
            returnsAfterInsert: false
        )
    }

    @Test("without Full Access the menu is restricted and never asks for the set")
    func whenNoFullAccess_thenRestrictedWithoutReading() {
        var reads = 0
        let menu = KeyboardMenu(hasFullAccess: false) {
            reads += 1
            return full()
        }
        #expect(menu.state == .restricted)
        #expect(reads == 0)
        #expect(menu.chips.isEmpty)
    }

    @Test("with Full Access: no set is unavailable, an empty set is empty, otherwise ready")
    func whenFullAccess_thenTheStateSaysWhatThereIs() {
        #expect(KeyboardMenu(hasFullAccess: true) { nil }.state == .unavailable)
        #expect(KeyboardMenu(hasFullAccess: true) { .empty }.state == .empty)
        #expect(KeyboardMenu(hasFullAccess: true) { full() }.state == .ready)
    }

    @Test("the chips are Recent, Pinned and Snippets when they have clips, then the chosen collections")
    func whenReady_thenTheChipsFollowTheShelf() {
        let menu = KeyboardMenu(hasFullAccess: true) { full() }
        #expect(menu.chips.map(\.title) == ["Recent", "Pinned", "Snippets", "Work"])
        #expect(menu.entries(for: .recent).map(\.text) == ["Basil pesto recipe", "tracking 1Z999"])
        #expect(menu.entries(for: .collection(work)).map(\.text) == ["Standup at 10", "12 Basil Lane"])
        #expect(menu.returnsAfterInsert == false)
    }

    @Test("a search looks through every clip once, a title starting with the word first")
    func whenSearched_thenPrefixMatchesLead() {
        let menu = KeyboardMenu(hasFullAccess: true) { full() }
        #expect(menu.entries(matching: "home").map(\.text) == ["12 Basil Lane"])
        #expect(menu.entries(matching: "BASIL").map(\.text) == ["Basil pesto recipe", "12 Basil Lane"])
        #expect(menu.entries(matching: "zzq").isEmpty)
    }

    @Test("a chosen collection with no clip to offer gets no chip")
    func whenACollectionIsEmpty_thenItHasNoChip() {
        let set = QuickInsertSet(
            createdAt: .now, entries: [entry("Basil pesto recipe", .recent)],
            collections: [QuickInsertCollection(id: UUID(), name: "Empty", symbolName: "folder", entryIDs: [])]
        )
        #expect(KeyboardMenu(hasFullAccess: true) { set }.chips.map(\.title) == ["Recent"])
    }

    @Test("Hebrew search ignores niqqud and matches final and non-final letters interchangeably")
    func whenHebrewSearched_thenNiqqudAndFinalsMatch() {
        let set = QuickInsertSet(
            createdAt: .now,
            entries: [
                entry("שָׁלוֹם עוֹלָם", .recent),
                entry("מכתב רשמי", .pinned, title: "מכתבים")
            ]
        )
        let menu = KeyboardMenu(hasFullAccess: true) { set }
        #expect(menu.entries(matching: "שלומ").map(\.text) == ["שָׁלוֹם עוֹלָם"])
        #expect(menu.entries(matching: "שלום").map(\.text) == ["שָׁלוֹם עוֹלָם"])
        #expect(menu.entries(matching: "מכתבימ").map(\.text) == ["מכתב רשמי"])
    }

    @Test("when keyboardEnabled is false in the set, the menu is unavailable with no chips or entries")
    func whenKeyboardDisabled_thenUnavailable() {
        let base = full()
        let disabled = QuickInsertSet(
            createdAt: base.createdAt,
            entries: base.entries,
            collections: base.collections,
            returnsAfterInsert: base.returnsAfterInsert,
            keyboardEnabled: false
        )
        let menu = KeyboardMenu(hasFullAccess: true) { disabled }
        #expect(menu.state == .unavailable)
        #expect(menu.chips.isEmpty)
        #expect(menu.entries(for: .recent).isEmpty)
        #expect(menu.entries(matching: "Basil").isEmpty)
    }
}
