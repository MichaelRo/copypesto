// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import Pesto

@Suite("Counts read correctly for one and for many")
struct PluralStringsTests {
    @Test("clips, collections and deletions use the singular for one", arguments: [
        (1, "1 clip"), (0, "0 clips"), (2, "2 clips"), (30, "30 clips")
    ])
    func clips_pluralise(count: Int, expected: String) {
        #expect(CountText.clips(count) == expected)
    }

    @Test("the other counted nouns pluralise the same way")
    func otherNouns_pluralise() {
        #expect(CountText.collections(1) == "1 collection")
        #expect(CountText.collections(3) == "3 collections")
        #expect(CountText.deletions(1) == "1 deletion")
        #expect(CountText.deletions(4) == "4 deletions")
        #expect(CountText.alreadyHere(1) == "1 was already here.")
        #expect(CountText.alreadyHere(5) == "5 were already here.")
    }

    @Test("whole sentences with a count agree with it")
    func sentences_agree() {
        let one = 1
        let many = 12
        #expect(String(localized: "Clear \(one) clips?") == "Clear 1 clip?")
        #expect(String(localized: "Clear \(many) clips?") == "Clear 12 clips?")
        #expect(String(localized: "Cleared \(one) clips.") == "Cleared 1 clip.")
        #expect(String(localized: "\(one) clips imported.") == "1 clip imported.")
        #expect(String(localized: "\(many) clips imported.") == "12 clips imported.")
        #expect(String(localized: "\(one) clips selected") == "1 clip selected")
        #expect(String(localized: "Blurred \(one) pictures.") == "Blurred 1 picture.")
        #expect(String(localized: "Blurred \(many) pictures.") == "Blurred 12 pictures.")
        #expect(String(localized: "Blurred \(one) sensitive clips.") == "Blurred 1 sensitive clip.")
        #expect(String(localized: "Blurred \(many) sensitive clips.") == "Blurred 12 sensitive clips.")
        #expect(String(localized: "\(one) clips match") == "1 clip matches")
        #expect(String(localized: "\(many) clips match") == "12 clips match")
        #expect(String(localized: "\(one) snippets imported.") == "1 snippet imported.")
        #expect(String(localized: "\(many) snippets imported.") == "12 snippets imported.")
        #expect(String(localized: "\(one) without a placeholder were pinned as clips.")
            == "1 without a placeholder was pinned as a clip.")
        #expect(String(localized: "\(many) snippets have tokens Pesto does not fill in, left as typed.")
            == "12 snippets have tokens Pesto does not fill in, left as typed.")
        #expect(String(localized: "Hid \(one) pictures.") == "Hid 1 picture.")
        #expect(String(localized: "Hid \(many) pictures.") == "Hid 12 pictures.")
        #expect(String(localized: "Hid \(one) sensitive clips.") == "Hid 1 sensitive clip.")
        #expect(String(localized: "Hid \(many) sensitive clips.") == "Hid 12 sensitive clips.")
        #expect(String(localized: "\(one) days") == "1 day")
    }

    @Test("a list of counts is joined the way the language joins a list")
    func list_joins() {
        let text = CountText.list([CountText.clips(5), CountText.collections(2), CountText.deletions(1)])
        #expect(text.contains("5 clips") && text.contains("2 collections") && text.contains("1 deletion"))
    }

    @Test("settings and shelf sentences agree with their count")
    func settingsSentences_agree() {
        #expect(AuthenticationGracePicker.title(1) == "1 minute")
        #expect(AuthenticationGracePicker.title(5) == "5 minutes")
        #expect(String(localized: "\(1) characters") == "1 character")
        #expect(String(localized: "\(2400) characters") == "2,400 characters")
        #expect(String(localized: "This deletes all \(1) clips, including pinned ones.") ==
            "This deletes 1 clip, even if it is pinned.")
        #expect(String(localized: "This deletes all \(7) clips, including pinned ones.") ==
            "This deletes all 7 clips, including pinned ones.")
    }

    @Test("a shortcut conflict names one shortcut or several")
    func shortcutConflict_agrees() {
        let one = String(localized: "\(1) shortcut conflicts: \("Open the shelf")")
        let two = String(localized: "\(2) shortcut conflicts: \("Open the shelf, Paste plain text")")
        #expect(one == "1 shortcut is already registered by another app: Open the shelf.")
        #expect(two == "2 shortcuts are already registered by another app: Open the shelf, Paste plain text.")
    }
}
