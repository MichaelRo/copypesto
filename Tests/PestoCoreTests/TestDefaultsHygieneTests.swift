// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Tests keep their preferences out of ~/Library/Preferences")
struct TestDefaultsHygieneTests {
    @Test(
        "no test opens a named defaults suite: removePersistentDomain leaves a plist behind, so use ThrowawayDefaults"
    )
    func whenTestsOpenSuites_thenOnlyThroughTheHelper() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let allowed: Set = ["ThrowawayDefaults.swift", "TestDefaultsHygieneTests.swift"]
        let domainAPIs = try NSRegularExpression(pattern: #"\b(?:remove|set)?[pP]ersistentDomain\("#)
        var offenders: [String] = []
        var scanned = 0
        let files = try #require(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
        for case let file as URL in files
            where file.pathExtension == "swift" && !allowed.contains(file.lastPathComponent)
        {
            scanned += 1
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains("UserDefaults(suiteName:") { offenders.append(file.lastPathComponent) }
            let range = NSRange(source.startIndex..., in: source)
            if domainAPIs.firstMatch(in: source, range: range) != nil, !source.contains("ThrowawayDefaults") {
                offenders
                    .append(
                        "\(file.lastPathComponent) (a persistent-domain call on a domain not from ThrowawayDefaults)"
                    )
            }
        }
        #expect(scanned > 100, "the tests were not found")
        #expect(offenders.isEmpty, "use ThrowawayDefaults.make() in \(offenders)")
    }
}
