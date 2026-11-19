// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The keyboard as a small Pesto shelf (ADRs 0061, 0062, 0063; the search key opens `KeyboardSearchPage`): chips on top
/// like the Mac shelf's (the word typed before
/// switching, then Recent, Pinned, Snippets and the chosen collections), the clips as cards in a row that scrolls
/// sideways (two rows on iPhone, one on iPad), or the numbers pad, above Globe, 123, Space, Return and Delete.
struct KeyboardRootView: View {
    let model: KeyboardModel
    let keys: KeyboardKeys
    weak var controller: UIInputViewController?

    @State private var showsPad = false
    @State private var chip: KeyboardMenu.Chip?
    @State private var inserted: UUID?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // Searched once per pass: every chip and card below reads the same matches.
        let matches = word.map(model.menu.entries(matching:)) ?? []
        Group {
            if model.isSearching {
                KeyboardSearchPage(
                    model: model, controller: controller,
                    pick: { entry, longPress in
                        setSearching(false)
                        insert(entry, longPress: longPress, matches: [])
                    },
                    close: { setSearching(false) }
                )
            } else {
                VStack(spacing: 6) {
                    if model.menu.state == .ready, !showsPad { chipRow(matches: matches) }
                    content(matches: matches)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    bottomRow
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .tint(BrandAccent.color)
    }

    /// The word the person typed before switching, unless they took it off with its chip.
    private var word: String? {
        guard let word = model.word, word != model.dismissedWord else { return nil }
        return word
    }

    private var selectedChip: KeyboardMenu.Chip? {
        let available = model.menu.chips.map(\.chip)
        if let chip, available.contains(chip) { return chip }
        return available.first
    }

    private func shown(_ matches: [QuickInsertEntry]) -> [QuickInsertEntry] {
        if !matches.isEmpty { return matches }
        guard let selectedChip else { return [] }
        return model.menu.entries(for: selectedChip)
    }

    @ViewBuilder
    private func content(matches: [QuickInsertEntry]) -> some View {
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
            shelf(matches: matches)
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

    private func chipRow(matches: [QuickInsertEntry]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let word {
                    KeyboardChip(
                        title: "\u{201C}\(word)\u{201D}", symbolName: "xmark", isSelected: !matches.isEmpty,
                        isDimmed: matches.isEmpty
                    ) { model.dismissedWord = word }
                        .accessibilityLabel(Text("Matching \(word)"))
                        .accessibilityHint(Text("Shows all clips again"))
                }
                ForEach(model.menu.chips, id: \.chip) { label in
                    KeyboardChip(
                        title: label.title, symbolName: label.symbolName,
                        isSelected: matches.isEmpty && label.chip == selectedChip, isDimmed: false
                    ) {
                        if let word { model.dismissedWord = word }
                        chip = label.chip
                    }
                }
            }
        }
        .scrollEdgeEffectHidden(true, for: .all)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shelf(matches: [QuickInsertEntry]) -> some View {
        let rows = Array(repeating: GridItem(.flexible(), spacing: 6), count: sizeClass == .regular ? 1 : 2)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 6) {
                ForEach(shown(matches)) { entry in
                    KeyboardClipKey(entry: entry, isInserted: inserted == entry.id)
                        .frame(width: sizeClass == .regular ? 180 : 150)
                        .onTapGesture { insert(entry, longPress: false, matches: matches) }
                        .onLongPressGesture(minimumDuration: 0.4) { insert(entry, longPress: true, matches: matches) }
                        .accessibilityAction { insert(entry, longPress: false, matches: matches) }
                        .accessibilityAction(named: model.menu.returnsAfterInsert
                            ? Text("Insert and Stay") : Text("Insert and Return"))
                        {
                            insert(entry, longPress: true, matches: matches)
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
    private func insert(_ entry: QuickInsertEntry, longPress: Bool, matches: [QuickInsertEntry]) {
        if let word, matches.contains(entry) {
            // The field is read again now: if the caret moved, or the word was already replaced, nothing is deleted.
            let count = KeyboardWord.deletions(
                replacing: word,
                before: keys.contextBefore(),
                after: keys.contextAfter()
            )
            for _ in 0..<(count ?? 0) {
                keys.deleteBackward()
            }
            model.dismissedWord = word
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

    private func setSearching(_ isOn: Bool) {
        if isOn { model.openSearch() } else { model.closeSearch() }
        keys.relayout()
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
            if model.menu.state == .ready {
                Button { setSearching(true) } label: {
                    Image(systemName: "magnifyingglass").frame(width: 44, height: 40)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Search Clips"))
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
