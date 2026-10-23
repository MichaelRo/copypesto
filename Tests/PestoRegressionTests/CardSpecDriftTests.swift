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
            ("Header height", CardLayout.headerHeight),
            ("App tile", CardLayout.appTileSize),
            ("Space under the header", CardLayout.bodyTopPadding),
            ("Gap between paragraphs", CardLayout.paragraphGap),
            ("Footer reserve", CardLayout.footerReserve)
        ]
        for (name, points) in rows {
            let row = "| \(name) | \(Int(points)) pt | \(rem(points)) |"
            #expect(spec.contains(row), "website-shelf-spec.md is out of date: expected \(row)")
        }
    }

    @Test("the app wash share in the spec is the one the card draws")
    func specMatchesWash() throws {
        let card = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/ClipboardCard+Parts.swift"),
            encoding: .utf8
        )
        let match = try #require(card.firstMatch(of: /static let appWashShare = 0\.(\d+)/))
        let spec = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("docs/design/website-shelf-spec.md"),
            encoding: .utf8
        )
        #expect(spec.contains("\(match.1) %") || spec.contains("\(match.1)%"), "spec must name the \(match.1)% wash")
    }
}
