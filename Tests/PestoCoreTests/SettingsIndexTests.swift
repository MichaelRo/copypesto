// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("Settings search index")
struct SettingsIndexTests {
    @Test("an empty or blank query finds nothing")
    func whenBlank_thenNoResults() {
        #expect(SettingsIndex.search("").isEmpty)
        #expect(SettingsIndex.search("   ").isEmpty)
    }

    @Test("a setting is found by a word in its title", arguments: [
        ("blur", "Privacy"), ("login", "General"), ("accent", "Appearance"), ("plain text", "Shortcuts"),
        ("apple intelligence", "General"), ("export", "Data"), ("exclusion", "Privacy"), ("insights", "Data")
    ])
    func whenTitleWord_thenFound(query: String, pane: String) {
        #expect(SettingsIndex.search(query).contains { $0.pane == pane }, "\(query) should reach \(pane)")
    }

    @Test("a setting is found by a synonym that is not in its title")
    func whenSynonym_thenFound() {
        #expect(SettingsIndex.search("password manager").contains { $0.pane == "Privacy" })
        #expect(SettingsIndex.search("startup").contains { $0.title.contains("Launch Pesto at login") })
        #expect(SettingsIndex.search("dark").contains { $0.pane == "Appearance" })
        #expect(SettingsIndex.search("touch id").contains { $0.title.contains("lock") || $0.title.contains("Lock") })
    }

    @Test("the two permission rows are found in the pane that actually shows them")
    func whenPermissionSearched_thenGeneralPane() {
        #expect(SettingsIndex.search("accessibility").contains { $0.pane == "General" })
        #expect(!SettingsIndex.search("accessibility").contains { $0.pane == "Privacy" })
        #expect(SettingsIndex.search("pasteboard").contains { $0.pane == "General" })
    }

    @Test("snippets and templates are found in their own pane")
    func whenSnippetSearched_thenSnippets() {
        #expect(SettingsIndex.search("snippet").contains { $0.pane == "Snippets" })
        #expect(SettingsIndex.search("template").contains { $0.pane == "Snippets" })
        #expect(!SettingsIndex.search("snippet").contains { $0.pane == "Collections" })
    }

    @Test("a search for updates finds the switch for automatic update checks in General")
    func whenUpdatesSearched_thenTheSwitchInGeneral() {
        #expect(SettingsIndex.search("check for updates").contains { $0.pane == "General" })
    }

    @Test("case, accents and word order do not matter, and every word has to match")
    func whenMessyQuery_thenStillFound() {
        #expect(!SettingsIndex.search("BLUR").isEmpty)
        #expect(SettingsIndex.search("size card").contains { $0.title.contains("Card size") })
        #expect(SettingsIndex.search("blur zebra").isEmpty)
    }

    @Test("results are ordered by how well the title matches")
    func whenSeveralMatch_thenTitleMatchesFirst() {
        let results = SettingsIndex.search("shortcut")
        #expect(results.first?.pane == "Shortcuts")
    }

    @Test("every pane can be reached, and every entry names a real pane")
    func whenIndexBuilt_thenConsistent() {
        let panes = [
            "General",
            "Appearance",
            "Privacy",
            "Shortcuts",
            "Collections",
            "Snippets",
            "Data"
        ]
        #expect(Set(SettingsIndex.entries.map(\.pane)) == Set(panes))
        #expect(Set(SettingsIndex.entries.map(\.title)).count == SettingsIndex.entries.count, "duplicate titles")
    }

    @Test("each setting is on the page about its topic, and there is no catch-all pane")
    func whenChecked_thenPanesMatchThePlan() {
        func pane(_ title: String) -> String? {
            SettingsIndex.entries.first { $0.title == title }?.pane
        }
        let expected = [
            "App exclusions": "Privacy",
            "Hide contents during screen sharing": "Privacy",
            "Encryption": "Privacy",
            "Keep up to a number of clips": "Data",
            "Strip URL tracking parameters": "Data",
            "Rebuild search index": "Data",
            "Paste from the floating window": "General",
            "Launch Pesto at login": "General",
            "Export clips": "Data"
        ]
        for (title, expectedPane) in expected {
            #expect(pane(title) == expectedPane, "\(title) should be in \(expectedPane)")
        }
        #expect(!SettingsIndex.entries.contains { $0.pane == "Advanced" })
    }
}
