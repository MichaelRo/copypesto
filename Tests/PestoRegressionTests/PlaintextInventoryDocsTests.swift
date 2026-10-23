// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// The guide gave a short list as "what is not encrypted" and SECURITY.md used it to define scope, while
/// the
/// store also holds masked previews (a card's last four digits), collection names and rules, clip kinds, pins and
/// counts.
/// These phrases name what is plaintext today; a new plaintext column needs a line in the guide and a phrase here.
@Suite("What the docs say is not encrypted")
struct PlaintextInventoryDocsTests {
    private func text(_ relative: String) throws -> String {
        try String(contentsOf: SourceTree.repositoryRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    private static let guidePhrases = [
        "the names of the apps clips came from", "when they were copied", "how big they are",
        "what kind each clip is", "whether it is pinned", "which collection it is in",
        "which clips are secrets", "last four digits", "the names, icons and rules of your collections",
        "colors you copied", "fingerprint of each picture",
        "preview of your latest clip that holds no secret", "your user account can read"
    ]

    private static let securityPhrases = [
        "app names, times and sizes", "clip kinds, pins and counts", "collection names and rules",
        "masked previews of secrets", "colors", "latest clip"
    ]

    @Test("the privacy guide lists every plaintext field")
    func guideNamesThePlaintext() throws {
        let guide = try text("docs/guide/privacy-and-security.md")
        for phrase in Self.guidePhrases {
            #expect(guide.contains(phrase), "the guide does not say: \(phrase)")
        }
    }

    @Test("SECURITY.md's scope text names the same things")
    func securityNamesThePlaintext() throws {
        let security = try text("SECURITY.md").replacingOccurrences(of: "\n  ", with: " ")
        for phrase in Self.securityPhrases {
            #expect(security.contains(phrase), "SECURITY.md does not say: \(phrase)")
        }
    }

    @Test("the Settings caption points to what stays readable")
    func settingsCaptionMentionsIt() throws {
        let caption = try text("Sources/Features/Settings/CaptureSettings.swift")
        #expect(caption.contains("stay readable"))
    }
}
