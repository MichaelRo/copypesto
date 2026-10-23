// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// Compact popover for editing an existing collection directly from the overlay chip bar.
/// Presents inline without distorting the overlay panel (unlike .sheet).
struct CollectionEditPopover: View {
    @Environment(\.pestoAccent) private var accent
    var existing: Pinboard
    var onSave: (String, String, String) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState: AppState

    @State private var name = ""
    @State private var symbol = "folder.fill"
    @State private var colorHex = "007AFF"
    @State private var showSymbolPicker = false
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    @State private var colorSave: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Collection")
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                Button {
                    showSymbolPicker.toggle()
                } label: {
                    symbolLabel
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSymbolPicker, arrowEdge: .bottom) {
                    emojiPickerPopover
                }

                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .scaledFont(size: 12, weight: .medium)
                    .focused($nameFocused)
                    .onSubmit { dismiss() }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
            }

            CollectionColorRow(colorHex: $colorHex) { _ in saveColorSoon() }

            Divider()

            if confirmingDelete {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Delete this collection? The clips in it stay in your history.")
                        .scaledFont(size: 11)
                        .pestoQuiet()
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Cancel") { confirmingDelete = false }
                        Button("Delete", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        .foregroundStyle(Color.statusBad)
                    }
                    .scaledFont(size: 11)
                    .buttonStyle(.plain)
                }
            } else {
                Button("Delete Collection", role: .destructive) { confirmingDelete = true }
                    .scaledFont(size: 11)
                    .foregroundStyle(Color.statusBad)
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 248)
        .onAppear {
            name = existing.name
            symbol = existing.symbolName
            colorHex = existing.colorHex
            appState.isEditingCollection = true
        }
        .task {
            // The popover's field is inserted in the same update that opens it; focusing in that pass finds no field.
            try? await Task.sleep(for: .milliseconds(60))
            nameFocused = true
        }
        .onDisappear {
            appState.isEditingCollection = false
            colorSave?.cancel()
            // Saved once, when the popover closes: saving on every keystroke refreshed both grids for each letter.
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let changed = trimmed != existing.name || !CollectionPalette.isSame(colorHex, existing.colorHex)
            if !confirmingDelete, !trimmed.isEmpty, changed { onSave(trimmed, symbol, colorHex) }
        }
    }

    /// The colour panel reports every colour while it is dragged: only the one it settles on is saved.
    private func saveColorSoon() {
        colorSave?.cancel()
        colorSave = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { onSave(trimmed, symbol, colorHex) }
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
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { onSave(trimmed, emoji, colorHex) }
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
            Text(symbol).font(.system(size: 14))
        } else {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .pestoQuiet()
        }
    }
}
