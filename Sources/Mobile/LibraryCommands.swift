// SPDX-License-Identifier: MIT
import SwiftUI

/// What the library page and the focused card can do, for the keyboard shortcuts and the iPad's menu bar (and the
/// list a held ⌘ shows).
struct ListCommandActions {
    let newNote: () -> Void
    let search: () -> Void
    let toggleDetail: () -> Void
    var copySelected: (() -> Void)?
}

struct ClipCommandActions {
    let isPinned: Bool
    let copy: () -> Void
    let togglePin: () -> Void
    let delete: () -> Void
}

extension FocusedValues {
    @Entry var listCommands: ListCommandActions?
    @Entry var clipCommands: ClipCommandActions?
}

struct LibraryCommands: Commands {
    @FocusedValue(\.listCommands) private var list
    @FocusedValue(\.clipCommands) private var clip

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { list?.newNote() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(list == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button(list?.copySelected != nil ? "Copy Selected" : "Copy Clip") {
                if let copySelected = list?.copySelected {
                    copySelected()
                } else {
                    clip?.copy()
                }
            }
            .keyboardShortcut("c", modifiers: [.shift, .command])
            .disabled(list?.copySelected == nil && clip == nil)
            Button(clip?.isPinned == true ? "Unpin" : "Pin") { clip?.togglePin() }
                .keyboardShortcut("p", modifiers: [.shift, .command])
                .disabled(clip == nil)
            Button("Delete Clip") { clip?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(clip == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Search") { list?.search() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(list == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Show Details") { list?.toggleDetail() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(list == nil)
        }
    }
}
