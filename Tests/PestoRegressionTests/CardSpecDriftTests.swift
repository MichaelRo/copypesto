// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing

@Suite("Website card spec")
struct CardSpecDriftTests {
    private func rem(_ points: CGFloat) -> String {
        String(format: "%g", Double(points / 16)) + "rem"
    }

    @Test("the values table of the website hand-off is the one CardLayout draws")
    func specMatchesCardLayout() throws {
        let spec = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("docs/design/website-shelf-spec.md"),
            encoding: .utf8
        )
        let rows: [(String, CGFloat)] = [
            ("Space above the content", CardLayout.contentTopInset),
            ("Source tile", CardLayout.sourceTileSize),
            ("Gap between paragraphs", CardLayout.paragraphGap),
            ("Footer reserve", CardLayout.footerReserve)
        ]
        for (name, points) in rows {
            let row = "| \(name) | \(Int(points)) pt | \(rem(points)) |"
            #expect(spec.contains(row), "website-shelf-spec.md is out of date: expected \(row)")
        }
    }

    @Test("the filter groups in the spec are the ones the search bar draws, in its order")
    func specMatchesTheFilterGroups() throws {
        let spec = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("docs/design/website-shelf-spec.md"),
            encoding: .utf8
        )
        let line = try #require(
            spec.components(separatedBy: "\n").first { $0.hasPrefix("Filter groups, in order: ") },
            "website-shelf-spec.md has no \"Filter groups, in order:\" line"
        )
        let listed = line.dropFirst("Filter groups, in order: ".count).dropLast().components(separatedBy: ", ")
        let barFile = try SourceTree.swiftFiles(in: "Features/CommandBar", minimum: 5)
            .first { $0.lastPathComponent == "CommandBarView.swift" }
        let bar = try String(contentsOf: #require(barFile), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"group\("(\w+)", id:"#)
        let drawn = pattern.matches(in: bar, range: NSRange(bar.startIndex..., in: bar)).compactMap { match in
            Range(match.range(at: 1), in: bar).map { String(bar[$0]) }
        }
        #expect(drawn == listed, "the search bar draws \(drawn) but website-shelf-spec.md lists \(listed)")
    }

    @Test("only a standalone color card computes detectedColor or badges as Color")
    func whenCardIsTextOrCodeWithColorLiteral_thenNeverBadgedAsColor() throws {
        let card = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/ClipboardCard+Parts.swift"),
            encoding: .utf8
        )
        #expect(card.contains("guard item.type == .color else { return nil }"))
        #expect(!card.contains("colorSwatchBadge"))
    }
}
