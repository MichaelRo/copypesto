// SPDX-License-Identifier: MIT
import SwiftUI

/// What the focused list and the focused clip can do, for the keyboard shortcuts and the iPad's menu bar.
struct ListCommandActions {
    let newNote: () -> Void
    let search: () -> Void
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
            Button("Copy Clip") { clip?.copy() }
                .keyboardShortcut("c", modifiers: [.shift, .command])
                .disabled(clip == nil)
            Button(clip?.isPinned == true ? "Unpin" : "Pin") { clip?.togglePin() }
                .keyboardShortcut("p", modifiers: .command)
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
    }
}
