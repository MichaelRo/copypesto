// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The keyboard as a small Pesto shelf (ADRs 0061, 0062): chips on top like the Mac shelf's (the word typed before
/// switching, then Recent, Pinned, Snippets and the chosen collections), the clips as cards in a row that scrolls
/// sideways (two rows on iPhone, one on iPad), or the numbers pad, above Globe, 123, Space, Return and Delete.
struct KeyboardRootView: View {
    let model: KeyboardModel
    let keys: KeyboardKeys
    weak var controller: UIInputViewController?

    @State private var showsPad = false
    @State private var chip: KeyboardMenu.Chip?
    @State private var dismissedWord: String?
    @State private var inserted: UUID?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 6) {
            if model.menu.state == .ready, !showsPad { chipRow }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .tint(BrandAccent.color)
    }

    /// The word the person typed before switching, unless they took it off with its chip.
    private var word: String? {
        guard let word = model.word, word != dismissedWord else { return nil }
        return word
    }

    private var matches: [QuickInsertEntry] {
        word.map(model.menu.entries(matching:)) ?? []
    }

    private var selectedChip: KeyboardMenu.Chip? {
        let available = model.menu.chips.map(\.chip)
        if let chip, available.contains(chip) { return chip }
        return available.first
    }

    private var shown: [QuickInsertEntry] {
        if !matches.isEmpty { return matches }
        guard let selectedChip else { return [] }
        return model.menu.entries(for: selectedChip)
    }

    @ViewBuilder
    private var content: some View {
        switch model.menu.state {
        case .restricted:
            VStack(spacing: 8) {
                note("To show your clips, allow Full Access in Settings > General > Keyboard > Keyboards > Pesto.")
                KeyboardPad(insert: keys.insert)
            }
        case _ where showsPad:
            KeyboardPad(insert: keys.insert)
        case .unavailable:
            note("Turn on Insert from Pesto in other apps in Pesto's Settings.")
        case .empty:
            note("No text clips yet. Clips with secrets never appear here.")
        case .ready:
            shelf
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let word {
                    KeyboardChip(
                        title: "\u{201C}\(word)\u{201D}", symbolName: "xmark", isSelected: !matches.isEmpty,
                        isDimmed: matches.isEmpty
                    ) { dismissedWord = word }
                        .accessibilityLabel(Text("Matching \(word)"))
                        .accessibilityHint(Text("Shows all clips again"))
                }
                ForEach(model.menu.chips, id: \.chip) { label in
                    KeyboardChip(
                        title: label.title, symbolName: label.symbolName,
                        isSelected: matches.isEmpty && label.chip == selectedChip, isDimmed: false
                    ) {
                        if let word { dismissedWord = word }
                        chip = label.chip
                    }
                }
            }
        }
        .scrollEdgeEffectHidden(true, for: .all)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var shelf: some View {
        let rows = Array(repeating: GridItem(.flexible(), spacing: 6), count: sizeClass == .regular ? 1 : 2)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 6) {
                ForEach(shown) { entry in
                    KeyboardClipKey(entry: entry, isInserted: inserted == entry.id)
                        .frame(width: sizeClass == .regular ? 180 : 150)
                        .onTapGesture { insert(entry, longPress: false) }
                        .onLongPressGesture(minimumDuration: 0.4) { insert(entry, longPress: true) }
                        .accessibilityAction { insert(entry, longPress: false) }
                        .accessibilityAction(named: Text(model.menu
                                .returnsAfterInsert ? "Insert and Stay" : "Insert and Return"))
                        {
                            insert(entry, longPress: true)
                        }
                }
            }
        }
        .scrollEdgeEffectHidden(true, for: .all)
        .id(shownIdentity)
    }

    /// A new chip or search starts the row at its first card.
    private var shownIdentity: String {
        word.map { "word:\($0)" } ?? "\(String(describing: selectedChip))"
    }

    /// A tap does what the person chose in Settings (return to their keyboard, or stay); a long press does the other.
    /// A clip picked from a search replaces the word it was found by.
    private func insert(_ entry: QuickInsertEntry, longPress: Bool) {
        if let word, matches.contains(entry) {
            for _ in 0..<KeyboardWord.deletions(for: word) {
                keys.deleteBackward()
            }
        }
        keys.insert(entry.insertionText())
        if model.menu.returnsAfterInsert != longPress {
            keys.switchKeyboard()
            return
        }
        inserted = entry.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if inserted == entry.id { inserted = nil }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if model.showsGlobeKey {
                GlobeKey(controller: controller)
                    .frame(width: 44, height: 40)
            }
            if model.menu.state != .restricted {
                Button { showsPad.toggle() } label: {
                    padToggleLabel.frame(width: 52, height: 40)
                }
                .buttonStyle(.bordered)
            }
            Button { keys.insert(" ") } label: {
                Text("Space").frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
            .buttonRepeatBehavior(.enabled)
            Button { keys.insert("\n") } label: {
                Image(systemName: "return").frame(width: 44, height: 40)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("Return"))
            Button(action: keys.deleteBackward) {
                Image(systemName: "delete.left").frame(width: 44, height: 40)
            }
            .buttonStyle(.bordered)
            .buttonRepeatBehavior(.enabled)
            .accessibilityLabel(Text("Delete"))
        }
        .font(.body)
        .tint(.primary)
    }

    @ViewBuilder
    private var padToggleLabel: some View {
        if showsPad {
            Image(systemName: "rectangle.on.rectangle")
                .accessibilityLabel(Text("Clips"))
        } else {
            Text(verbatim: "123")
                .accessibilityLabel(Text("Numbers"))
        }
    }
}
