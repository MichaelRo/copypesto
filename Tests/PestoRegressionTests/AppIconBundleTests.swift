// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import Testing

/// The app icon has a dark appearance of its own (a dark ground and a P that still reads); clear and tinted are derived
/// by the
/// system from the same layers. The bundle is checked here because Icon Composer silently ignores a key it does not
/// know, so a wrong shape would only show as a plain green icon in dark mode.
@Suite("The app icon's appearances")
struct AppIconBundleTests {
    private var bundle: URL {
        SourceTree.sources.appendingPathComponent("Resources/Pesto.icon")
    }

    private func document() throws -> [String: Any] {
        let data = try Data(contentsOf: bundle.appendingPathComponent("icon.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("the dark appearance has its own fill")
    func darkHasItsOwnFill() throws {
        let fills = try #require(try document()["fill-specializations"] as? [[String: Any]])

        #expect(fills.contains { $0["appearance"] == nil }, "the default fill is listed without an appearance")
        #expect(fills.contains { ($0["appearance"] as? String) == "dark" })
    }

    @Test("the P has its own dark layer, and the layer names it for the dark appearance")
    func darkHasItsOwnLetterLayer() throws {
        let groups = try #require(try document()["groups"] as? [[String: Any]])
        let layers = try #require(groups.first?["layers"] as? [[String: Any]])
        let names = try #require(layers.first?["image-name-specializations"] as? [[String: Any]])
        #expect(names
            .contains { ($0["appearance"] as? String) == "dark" && ($0["value"] as? String) == "letter-dark.svg" })
    }

    @Test("the P reads against the garlic front card in both appearances (3:1, a graphic)")
    func letterReadsOnTheFrontCard() throws {
        let card = try fill(of: "front-card.svg")
        for asset in ["letter.svg", "letter-dark.svg"] {
            let ratio = try ContrastRatio.between(fill(of: asset), card)
            #expect(ratio >= 3, "\(asset) is \(ratio):1 on the front card")
        }
    }

    private func fill(of asset: String) throws -> String {
        let svg = try String(contentsOf: bundle.appendingPathComponent("Assets/\(asset)"), encoding: .utf8)
        let match = try #require(svg.firstMatch(of: /fill="#([0-9A-Fa-f]{6})"/), "\(asset) has no fill")
        return String(match.output.1)
    }

    @Test("the generator writes the dark layer too, so regenerating the layers does not drop it")
    func generatorWritesTheDarkLetter() throws {
        let script = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("design/source/icon-layers.swift"),
            encoding: .utf8
        )

        #expect(script.contains("letter-dark.svg"))
    }
}
