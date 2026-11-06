// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("The card's context menu reads the covered list")
struct CoveredMenuWiringTests {
    @Test("every CardMenuItem is asked for in the menu code, so none can bypass the covered list")
    func everyItemIsGated() throws {
        let source = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/ClipboardCard+ContextMenu.swift"),
            encoding: .utf8
        )
        for item in CardMenuItem.allCases {
            #expect(source.contains("offers(.\(item))"), "offers(.\(item)) is not in the menu code")
        }
    }

    @Test("every VoiceOver action that names or changes a clip is gated by the covered list")
    func voiceOverActionsAreGated() throws {
        let gated: [(file: String, expected: [String])] = [
            ("Features/Grid/CardEditActions.swift", ["rename", "note", "tag"]),
            ("Features/Grid/CardMoreActions.swift", ["pin", "openLink", "tag"])
        ]
        for (file, expected) in gated {
            let source = try String(contentsOf: SourceTree.sources.appendingPathComponent(file), encoding: .utf8)
            #expect(!source.contains(".accessibilityAction(named"), "\(file) has an ungated named action")
            for name in expected {
                #expect(source.contains("offers(.\(name))"), "offers(.\(name)) is not in \(file)")
            }
        }
    }

    @Test("the card's own VoiceOver actions are only ones a covered card may offer")
    func cardOwnActionsAreCoveredSafe() throws {
        let source = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/ClipboardCard.swift"),
            encoding: .utf8
        )
        let allowed: Set = ["Show", "Copy", "Quick Look", "Delete"]
        let pattern = try NSRegularExpression(pattern: #"\.accessibilityAction\(named: "([^"]+)"\)"#)
        let range = NSRange(source.startIndex..., in: source)
        let names = pattern.matches(in: source, range: range).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        }
        #expect(!names.isEmpty)
        for name in names {
            #expect(allowed.contains(name), "\(name) is a VoiceOver action outside the covered list")
        }
    }
}
