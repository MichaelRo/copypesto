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
            ("Features/Grid/CardMoreActions.swift", ["pin", "openLink", "tag", "copyRecognizedText"])
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

    @Test("the JSON and Markdown rows are drawn only inside Paste As and Copy As, and never on a concealed card")
    func structuredRowsAreGated() throws {
        let menu = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/ClipboardCard+ContextMenu.swift"),
            encoding: .utf8
        )
        let lines = menu.components(separatedBy: "\n")
        let uses = lines.indices.filter { lines[$0].contains("StructuredTransformRows(") }
        #expect(uses.count == 2, "one use in Copy As and one in Paste As")
        for use in uses {
            let before = lines[max(0, use - 2)..<use].joined(separator: "\n")
            #expect(before.contains("!concealment.isConcealed"), "line \(use + 1) is not behind the concealment check")
        }
        for (name, gate) in [
            ("copyTransformed", "offers(.copyTransformed)"),
            ("pasteTransformed", "offers(.pasteTransformed)")
        ] {
            #expect(menu.contains(gate), "\(name) menu is not behind \(gate)")
        }
        #expect(!CardMenuItem.coveredAllowed.contains(.copyTransformed))
        #expect(!CardMenuItem.coveredAllowed.contains(.pasteTransformed))
    }

    @Test("no VoiceOver action or other file reaches the structured transforms except the menu and the grid")
    func structuredTransformsHaveNoSideDoor() throws {
        let files = try SourceTree.files(in: "Features", minimum: 100)
        let allowed: Set = [
            "CardActions.swift", "GridView+Card.swift", "GridView+Actions.swift", "StructuredTransformRows.swift",
            "ClipboardCard+ContextMenu.swift"
        ]
        for file in files where !allowed.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(
                !text.contains("structuredTransforms") && !text.contains("StructuredPaste"),
                "\(SourceTree.relativePath(file)) reaches the structured transforms"
            )
        }
    }

    @Test("Copy Recognized Text is no covered-card entry and has no side door beyond its own files")
    func recognizedTextHasNoSideDoor() throws {
        #expect(!CardMenuItem.coveredAllowed.contains(.copyRecognizedText))
        #expect(!CardMenuItem.copyRecognizedText.isOffered(covered: true))
        let files = try SourceTree.files(in: "Features", minimum: 100)
        let allowed: Set = [
            "CardActions.swift", "GridView+Card.swift", "GridView+Actions.swift", "ClipboardCard+ContextMenu.swift",
            "ClipboardCard.swift", "ClipboardCard+HoverCard.swift", "CardMoreActions.swift", "CardDetailPopover.swift",
            "HoverCardCopyButton.swift"
        ]
        for file in files where !allowed.contains(file.lastPathComponent) {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(
                !text.contains("RecognizedText") && !text.contains("recognizedText"),
                "\(SourceTree.relativePath(file)) reaches the recognized text"
            )
        }
    }

    @Test(
        "the hover card's Copy Text is built only for a clip the shelf said offers it, and the grid asks the lock first"
    )
    func hoverButtonIsGated() throws {
        let hover = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/ClipboardCard+HoverCard.swift"),
            encoding: .utf8
        )
        #expect(hover.contains("actions.recognizedTextOffered?(item) == true"))
        #expect(hover.contains("onCopyRecognizedText: detailCopiesText ?"))
        let grid = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/GridView+Card.swift"),
            encoding: .utf8
        )
        #expect(grid.contains("!appState.isHistoryLockedNow() && RecognizedText.isOffered(for: $0)"))
        let actions = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("Features/Grid/GridView+Actions.swift"),
            encoding: .utf8
        )
        #expect(
            actions.contains("appState.copyRecognizedText(of: item)"),
            "the grid copies through AppState, where the lock is asked and the write is an ordinary copy (ADR 0037)"
        )
        let paste = try String(
            contentsOf: SourceTree.sources.appendingPathComponent("App/AppState+Paste.swift"), encoding: .utf8
        )
        let start = try #require(paste.range(of: "func copyRecognizedText(of item"))
        let rest = paste[start.lowerBound...]
        let copyBody = rest.prefix(upTo: rest.range(of: "\n    }\n")?.upperBound ?? rest.endIndex)
        #expect(copyBody.contains("!isHistoryLockedNow()"), "the lock is asked first")
        #expect(
            !copyBody.contains("writeToPasteboard"),
            "off the write gate, so the watcher records the text as a clip"
        )
    }
}
