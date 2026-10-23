// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// Automatic update checks only happen if the app's Info.plist asks Sparkle for them and names a feed; nothing else
/// tested that the shipped plist does, so a plist edit could have turned updates off without a failing test.
@Suite("Updates are checked automatically")
struct UpdateCheckConfigTests {
    private func plist() throws -> [String: Any] {
        let url = SourceTree.sources.appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("Sparkle is told to check by itself")
    func automaticChecksAreOn() throws {
        #expect(try plist()["SUEnableAutomaticChecks"] as? Bool == true)
    }

    @Test("the feed is the project's own host, over https, and updates are signed")
    func theFeedIsOurs() throws {
        let info = try plist()
        let feed = try #require((info["SUFeedURL"] as? String).flatMap(URL.init(string:)))
        #expect(feed.scheme == "https")
        #expect(feed.host == "copypesto.net")
        #expect(!(info["SUPublicEDKey"] as? String ?? "").isEmpty, "an update must be signed")
    }

    @Test("the app declares its category, so the Finder and Launchpad file it under Productivity")
    func theAppHasACategory() throws {
        #expect(try plist()["LSApplicationCategoryType"] as? String == "public.app-category.productivity")
    }

    @Test("Copy to Pesto is offered in the Services menu for selected text, and calls the provider by name")
    func theServiceIsDeclared() throws {
        let services = try #require(try plist()["NSServices"] as? [[String: Any]])
        let copy = try #require(services.first { ($0["NSMessage"] as? String) == "copyToPesto" })
        #expect((copy["NSMenuItem"] as? [String: String])?["default"] == "Copy to Pesto")
        #expect((copy["NSSendTypes"] as? [String])?.contains("NSStringPboardType") == true)
        #expect(copy["NSPortName"] as? String == "Pesto")
    }

    @Test("the two AppleScript commands that list things return lists, not one text with line breaks")
    func listCommandsReturnLists() throws {
        let sdef = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Resources/Pesto.sdef"), encoding: .utf8
        )
        for command in ["search history", "list collections"] {
            let start = try #require(sdef.range(of: "<command name=\"\(command)\""))
            let end = try #require(sdef.range(of: "</command>", range: start.upperBound..<sdef.endIndex))
            #expect(sdef[start.lowerBound..<end.upperBound].contains(#"<result type="text" list="yes""#), "\(command)")
        }
    }
}
