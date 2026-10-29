// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Demo-only code")
struct DemoOnlyCodeTests {
    private let files = [
        "Sources/Core/Seeding/LunchRushSeed.swift",
        "Sources/Core/Seeding/LunchRushMedia.swift",
        "Sources/Core/Runtime/ShowcaseArt+Basil.swift",
        "Sources/Core/Runtime/ShowcaseArt+Jar.swift"
    ]

    private let callers = [
        "Sources/App/AppDelegate+UITest.swift",
        "Sources/Core/Seeding/SeedFixtures.swift",
        "Sources/App/AppDelegate+MarketingBackdrop.swift"
    ]

    private func text(_ path: String) throws -> String {
        try String(contentsOf: SourceTree.repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("the demo video's clips and drawings are compiled out of a Release build, so the disk image has none")
    func whenReleaseIsBuilt_thenTheDemoVideoCodeIsNotInIt() throws {
        for path in files {
            let lines = try text(path).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            #expect(lines.first?.hasPrefix("// SPDX-License-Identifier") == true, "\(path)")
            #expect(lines.dropFirst().first == "#if DEBUG", "\(path) must start with #if DEBUG")
            #expect(lines.last(where: { !$0.isEmpty }) == "#endif", "\(path) must end with #endif")
        }
    }

    @Test("what calls the demo video's seed is compiled out with it")
    func whenReleaseIsBuilt_thenNoCallerIsLeftBehind() throws {
        for path in callers {
            let source = try text(path)
            let use = try #require(
                source.range(of: "seedLunchRush()") ?? source.range(of: "LunchRushSeed.captures()"),
                "\(path)"
            )
            let before = source[..<use.lowerBound]
            let opened = before.components(separatedBy: "#if DEBUG").count - 1
            let closed = before.components(separatedBy: "#endif").count - 1
            #expect(opened > closed, "\(path) calls the demo seed outside #if DEBUG")
        }
    }
}
