// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Compact inline row for creating a new collection directly inside the overlay chip bar.
/// Shows a name field, a context-sensitive emoji picker, and Save/Cancel affordances.
struct InlineCollectionCreator: View {
    @Environment(\.pestoAccent) private var accent
    @Binding var isPresented: Bool
    var onSave: (String, String) -> Void

    @State private var name = ""
    @State private var symbol = "folder.fill"
    @State private var showSymbolPicker = false
    @FocusState private var nameFocused: Bool
    @Environment(AppState.self) private var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Button {
                showSymbolPicker.toggle()
            } label: {
                symbolLabel
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSymbolPicker, arrowEdge: .bottom) {
                emojiPickerPopover
            }

            TextField("Name", text: $name)
                .accessibilityIdentifier(AccessibilityID.collectionNameField)
                .textFieldStyle(.plain)
                // Text size capped: the field has a fixed 100pt width in the toolbar row.
                .scaledFont(size: 11, weight: .medium, maxScale: 1.3)
                .focused($nameFocused)
                .frame(width: 100)
                .onSubmit { save() }
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }

            Button { save() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.secondary.opacity(0.4) : accent
                    )
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Create collection")

            Button { cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .pestoQuiet()
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassPanelBackground(in: Capsule(), interactive: true)
        .overlay(Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 0.5))
        .onAppear { appState.isEditingCollection = true }
        .task {
            // The field is inserted in the same update that starts the creator; focusing in that pass finds no
            // field, which left the name unselected until a click (the search field waits a beat too).
            try? await Task.sleep(for: .milliseconds(60))
            nameFocused = true
        }
        .onDisappear {
            appState.isEditingCollection = false
        }
    }

    // MARK: - Emoji picker popover

    private var emojiPickerPopover: some View {
        EmojiPickerPopover(
            name: name,
            selectedEmoji: symbol.unicodeScalars.first.map { $0.properties.isEmoji && $0.value > 0x238C } == true
                ? symbol : nil,
            onSelect: { emoji in
                symbol = emoji
                showSymbolPicker = false
            },
            onOpenSystem: {
                showSymbolPicker = false
                NSApp.orderFrontCharacterPalette(nil)
            }
        )
    }

    // MARK: - Symbol display

    @ViewBuilder
    private var symbolLabel: some View {
        if symbol.unicodeScalars.first.map({ $0.properties.isEmoji && $0.value > 0x238C }) == true {
            Text(symbol).font(.system(size: 12))
        } else {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .pestoQuiet()
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, symbol)
        isPresented = false
    }

    private func cancel() {
        isPresented = false
    }
}
