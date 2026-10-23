// SPDX-License-Identifier: MIT
import Foundation

/// The keys that work while the shelf is open, in the order Settings lists them. `KeyNavCoordinator` is what acts on
/// them; `ShelfKeyReferenceBindingTests` presses each listed key against it and checks that the handler named for it
/// fires, `ShelfKeyReferenceDriftTests` that every `ShelfCommand` is listed here and in `docs/guide/shortcuts.md`.
public struct ShelfKey: Equatable, Sendable, Identifiable {
    public var id: String {
        keys.joined(separator: " ") + " " + action
    }

    public let keys: [String]
    public let action: String
    /// macOS virtual key codes that trigger the action; empty for "start typing".
    public let keyCodes: [Int]
    public let needsCommand: Bool
    public let needsShift: Bool
    public let needsOption: Bool
    /// True for a key that only works while the search field is open.
    public let requiresSearch: Bool

    init(
        keys: [String], action: String, keyCodes: [Int], needsCommand: Bool, needsShift: Bool = false,
        needsOption: Bool = false, requiresSearch: Bool = false
    ) {
        self.keys = keys
        self.action = action
        self.keyCodes = keyCodes
        self.needsCommand = needsCommand
        self.needsShift = needsShift
        self.needsOption = needsOption
        self.requiresSearch = requiresSearch
    }
}

public enum ShelfKeyReference {
    public static let entries: [ShelfKey] = [
        ShelfKey(keys: ["←", "→"], action: "Move between clips", keyCodes: [123, 124], needsCommand: false),
        ShelfKey(
            keys: ["Home", "End"],
            action: "Jump to the first or last clip",
            keyCodes: [115, 119],
            needsCommand: false
        ),
        ShelfKey(
            keys: ["←", "→"], action: "With ⌥, move a screenful of clips", keyCodes: [123, 124], needsCommand: false,
            needsOption: true
        ),
        ShelfKey(
            keys: ["Page Up", "Page Down"], action: "Move a screenful of clips", keyCodes: [116, 121],
            needsCommand: false
        ),
        ShelfKey(
            keys: ["Return"], action: "Paste the focused clip (Paste One by One if several are selected)",
            keyCodes: [36], needsCommand: false
        ),
        ShelfKey(
            keys: ["⇧", "Return"], action: "Paste the focused clip as plain text", keyCodes: [36],
            needsCommand: false, needsShift: true
        ),
        ShelfKey(keys: ["Space"], action: "Select the focused clip", keyCodes: [49], needsCommand: false),
        ShelfKey(
            keys: ["⌫", "⌦"],
            action: "Delete the selected clips, or the focused one",
            keyCodes: [51, 117],
            needsCommand: false
        ),
        ShelfKey(
            keys: ["Esc"],
            action: "Go back one step: a prompt, Quick Look, the hover card or the selection, then the shelf",
            keyCodes: [53],
            needsCommand: false
        ),
        ShelfKey(keys: ["Type"], action: "Search your clips", keyCodes: [], needsCommand: false),
        ShelfKey(keys: ["⌘", "A"], action: "Select every clip shown", keyCodes: [0], needsCommand: true),
        ShelfKey(keys: ["⌘", "1–9"], action: "Paste the clip in that position", keyCodes: [18], needsCommand: true),
        ShelfKey(
            keys: ["⌘", "Return"], action: "Ask Pesto about the search", keyCodes: [36], needsCommand: true,
            requiresSearch: true
        ),
        ShelfKey(
            keys: ["⌘", "E"], action: "Show or hide a covered clip (⌘Return does too)", keyCodes: [14, 36],
            needsCommand: true
        ),
        ShelfKey(
            keys: ["Tab"], action: "In search, move through the filters", keyCodes: [48], needsCommand: false,
            requiresSearch: true
        ),
        ShelfKey(
            keys: ["⇧", "Tab"], action: "In search, move back through the filters", keyCodes: [48],
            needsCommand: false, needsShift: true, requiresSearch: true
        ),
        ShelfKey(
            keys: ["↓", "↑"], action: "In search, move through the results", keyCodes: [125, 126], needsCommand: false,
            requiresSearch: true
        ),
        ShelfKey(keys: ["⌘", "F"], action: "Search", keyCodes: [3], needsCommand: true),
        ShelfKey(keys: ["⌘", "K"], action: "Open the focused clip's actions", keyCodes: [40], needsCommand: true),
        ShelfKey(keys: ["⌘", "C"], action: "Copy the focused clip", keyCodes: [8], needsCommand: true),
        ShelfKey(keys: ["⌘", "Y"], action: "Quick Look the focused clip", keyCodes: [16], needsCommand: true),
        ShelfKey(keys: ["⌘", "S"], action: "Save the focused picture to Downloads", keyCodes: [1], needsCommand: true),
        ShelfKey(keys: ["⌘", "[", "]"], action: "Switch collections", keyCodes: [33, 30], needsCommand: true),
        ShelfKey(keys: ["⌘", "N"], action: "Add a collection", keyCodes: [45], needsCommand: true),
        ShelfKey(keys: ["⌘", "P"], action: "Paste the selected clips all at once", keyCodes: [35], needsCommand: true),
        ShelfKey(
            keys: ["⇧", "⌘", "P"], action: "Paste the selected clips one by one", keyCodes: [35], needsCommand: true,
            needsShift: true
        ),
        ShelfKey(keys: ["⌘", "Z"], action: "Undo the last delete or change", keyCodes: [6], needsCommand: true),
        ShelfKey(
            keys: ["⇧", "⌘", "Z"], action: "Redo what was undone", keyCodes: [6], needsCommand: true,
            needsShift: true
        ),
        ShelfKey(keys: ["⌘", ","], action: "Open Settings", keyCodes: [43], needsCommand: true)
    ]
}
