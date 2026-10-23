// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Shelf keys: the command table, Settings and the guide say the same")
struct ShelfKeyReferenceDriftTests {
    // swiftlint:disable cyclomatic_complexity
    /// Every `ShelfCommand`, with a label that `ShelfKeyReference` must list. The `switch` has no `default`, so a new
    /// case does not compile until it is added here and given a key in the list.
    private static func listing(for command: ShelfCommand) -> String {
        switch command {
        case .search: "⌘ F"
        case .previousCollection, .nextCollection: "⌘ [ ]"
        case .settings: "⌘ ,"
        case .newCollection: "⌘ N"
        case .pasteAll: "⌘ P"
        case .pasteOneByOne: "⇧ ⌘ P"
        case .undo: "⌘ Z"
        case .redo: "⇧ ⌘ Z"
        case .actions: "⌘ K"
        case .copy: "⌘ C"
        case .saveImage: "⌘ S"
        case .quickLook: "⌘ Y"
        case .selectAll: "⌘ A"
        case .pasteNth: "⌘ 1–9"
        case .returnKey: "⌘ Return"
        case .showHidden: "⌘ E"
        }
    }

    // swiftlint:enable cyclomatic_complexity

    private static let commands: [ShelfCommand] = [
        .search, .previousCollection, .nextCollection, .settings, .newCollection, .pasteAll, .pasteOneByOne, .undo,
        .redo, .actions, .copy, .saveImage, .quickLook, .selectAll, .pasteNth(1), .returnKey, .showHidden
    ]

    @Test("every command the shelf takes is listed in Settings")
    func everyCommandIsListed() {
        let listed = ShelfKeyReference.entries.map { $0.keys.joined(separator: " ") }
        let missing = Self.commands.map(Self.listing(for:)).filter { label in
            !listed.contains { $0 == label || $0.hasPrefix(label + " ") }
        }
        #expect(missing.isEmpty, "not in ShelfKeyReference: \(missing)")
    }

    @Test("every listed key is the one the command table resolves to the command it is listed for")
    func listedCommandKeysResolve() {
        for entry in ShelfKeyReference.entries where entry.needsCommand && !entry.keyCodes.isEmpty {
            for code in entry.keyCodes {
                #expect(
                    ShelfCommand.resolve(characters: nil, keyCode: UInt16(code), shift: entry.needsShift) != nil,
                    "\(entry.id): key code \(code) is no ⌘ command"
                )
            }
        }
    }

    @Test("the keyboard guide names every key Settings lists")
    func guideNamesEveryListedKey() throws {
        let guide = try String(
            contentsOf: SourceTree.repositoryRoot.appendingPathComponent("docs/guide/shortcuts.md"), encoding: .utf8
        )
        let modifiers: Set = ["⇧", "⌘", "⌥", "⌃"]
        var missing: [String] = []
        for entry in ShelfKeyReference.entries {
            let held = entry.keys.filter { modifiers.contains($0) }.joined()
            let keys = entry.keys.filter { !modifiers.contains($0) }.map { $0 == "1–9" ? "1" : $0 }
            if keys == ["Type"] { continue }
            for key in keys where !guide.contains("**\(held)\(key)**") {
                missing.append("\(held)\(key)")
            }
        }
        #expect(missing.isEmpty, "docs/guide/shortcuts.md has no bold key for: \(missing)")
    }
}
