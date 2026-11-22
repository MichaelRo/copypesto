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
        #expect(QuickInsertMenu(set: .locked()).state == .locked)
        let expiring = set.withExpiresAt(Date(timeIntervalSince1970: 1000))
        #expect(QuickInsertMenu(set: expiring, now: Date(timeIntervalSince1970: 999)).state == .ready)
        #expect(QuickInsertMenu(set: expiring, now: Date(timeIntervalSince1970: 1000)).state == .locked)
        #expect(QuickInsertMenu(set: .empty).state == .empty)
        #expect(QuickInsertMenu(set: set).state == .ready)
    }

    @Test("All returns one flat group with Pinned and Snippets first, then remaining newest-first")
    func whenGrouped_thenSectionsAreInOrder() {
        #expect(QuickInsertMenu(set: set).groups(matching: "").map(\.entries.count) == [4])
        #expect(QuickInsertMenu(set: set).groups(matching: "").first?.entries.map(\.section) == [
            .pinned,
            .snippets,
            .recent,
            .recent
        ])
        let noSnippets = QuickInsertSet(createdAt: .now, entries: set.entries.filter { $0.section != .snippets })
        #expect(QuickInsertMenu(set: noSnippets).groups(matching: "").first?.entries.map(\.section) == [
            .pinned,
            .recent,
            .recent
        ])
    }

    @Test("a search matches the title or the text, ignoring case and accents, and returns a flat All group")
    func whenSearched_thenOnlyMatchesRemain() {
        let menu = QuickInsertMenu(set: set)

        #expect(menu.groups(matching: "basil").flatMap(\.entries).map(\.section) == [.pinned, .recent])
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

    @Test("when autoFillEnabled is false in the set, the menu is unavailable with no groups")
    func whenAutoFillDisabled_thenUnavailable() {
        let disabled = QuickInsertSet(
            createdAt: .now,
            entries: [entry("12 Basil Lane", .pinned, title: "Home")],
            autoFillEnabled: false
        )
        let menu = QuickInsertMenu(set: disabled)
        #expect(menu.state == .unavailable)
        #expect(menu.groups(matching: "").isEmpty)
    }

    @Test("legacy QuickInsertSet JSON without keyboardEnabled or autoFillEnabled decodes both as true")
    func whenLegacyQuickInsertSetDecoded_thenFlagsDefaultToTrue() throws {
        let legacyJSON = """
        {
            "createdAt": 1800000000,
            "entries": []
        }
        """
        let decoded = try JSONDecoder().decode(QuickInsertSet.self, from: Data(legacyJSON.utf8))
        #expect(decoded.keyboardEnabled)
        #expect(decoded.autoFillEnabled)
    }

    @Test("Setting keys for keyboard, autoFill, and widgets have expected defaults and are registered")
    func whenSettingsChecked_thenDefaultsAndAllNamesMatch() {
        #expect(Setting.keyboardEnabled.defaultValue == true)
        #expect(Setting.autoFillEnabled.defaultValue == true)
        #expect(Setting.widgetsEnabled.defaultValue == true)
        #expect(Setting.allNames.contains(Setting.keyboardEnabled.name))
        #expect(Setting.allNames.contains(Setting.autoFillEnabled.name))
        #expect(Setting.allNames.contains(Setting.widgetsEnabled.name))
    }

    @Test("QuickInsertSelection.Options carries keyboardEnabled and autoFillEnabled")
    func whenOptionsConstructed_thenFlagsArePreserved() {
        let defaults = QuickInsertSelection.Options()
        #expect(defaults.keyboardEnabled)
        #expect(defaults.autoFillEnabled)

        let custom = QuickInsertSelection.Options(
            storedCollections: "",
            returnsAfterInsert: true,
            keyboardEnabled: false,
            autoFillEnabled: false
        )
        #expect(!custom.keyboardEnabled)
        #expect(!custom.autoFillEnabled)
    }

    @Test("QuickInsertMenu builds filter chips and filters groups by chip")
    func whenFilteredByChip_thenOnlyMatchingGroupReturns() {
        let menu = QuickInsertMenu(set: set)
        #expect(menu.chips.map(\.chip) == [.all, .pinned, .snippets])
        #expect(menu.groups(matching: "", chip: .pinned).map(\.section) == [.pinned])
        #expect(menu.groups(matching: "", chip: .snippets).map(\.section) == [.snippets])
        #expect(menu.groups(matching: "", chip: .all).flatMap(\.entries).map(\.section) == [
            .pinned,
            .snippets,
            .recent,
            .recent
        ])
    }

    @Test("Interactive fill-in snippets are kept for AutoFill but filtered out of KeyboardMenu")
    func whenFillInSnippetPresent_thenAutoFillKeepsItAndKeyboardSkipsIt() {
        #expect(TemplateExpander.fillsWithoutSystemContext("Hi {{name}}, {{date}}"))
        #expect(!TemplateExpander.fillsWithoutSystemContext("Paste: {{clipboard}}"))
        #expect(!TemplateExpander.fillsWithoutSystemContext("App: {{app}}"))

        let fillIn = QuickInsertEntry(
            id: UUID(), section: .snippets, kind: .text, title: "Greeting", text: "Hi {{name}}",
            expandsOnInsert: true, date: .now, source: nil, sourceIsThisDevice: true
        )
        let plain = QuickInsertEntry(
            id: UUID(), section: .snippets, kind: .text, title: "Today", text: "On {{date}}",
            expandsOnInsert: true, date: .now, source: nil, sourceIsThisDevice: true
        )
        let combined = QuickInsertSet(createdAt: .now, entries: [fillIn, plain])
        let autoFill = QuickInsertMenu(set: combined)
        let keyboard = KeyboardMenu(hasFullAccess: true) { combined }
        #expect(autoFill.groups(matching: "").first?.entries.map(\.id) == [fillIn.id, plain.id])
        #expect(keyboard.entries(for: .snippets).map(\.id) == [plain.id])
    }
}
