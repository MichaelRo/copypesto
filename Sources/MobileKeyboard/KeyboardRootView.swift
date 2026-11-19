// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The keyboard: the clips as Pesto cards in one list (Pinned, Snippets, Recent; no search field, since this keyboard
/// is the one typing), or the numbers pad, above a row of Globe, 123, Space, Return and Delete.
struct KeyboardRootView: View {
    let model: KeyboardModel
    let keys: KeyboardKeys
    weak var controller: UIInputViewController?

    @State private var showsPad = false
    @State private var inserted: UUID?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 8) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .tint(BrandAccent.color)
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
            list
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

    private var list: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: sizeClass == .regular ? 3 : 2)
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(model.menu.groups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            KeyboardClipKey(entry: entry, isInserted: inserted == entry.id)
                                .onTapGesture { insert(entry, thenSwitch: true) }
                                .onLongPressGesture(minimumDuration: 0.4) { insert(entry, thenSwitch: false) }
                                .accessibilityAction { insert(entry, thenSwitch: true) }
                                .accessibilityAction(named: Text("Insert and Stay")) {
                                    insert(entry, thenSwitch: false)
                                }
                        }
                    } header: {
                        Text(KeyboardClipKey.title(of: group.section))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
        .scrollEdgeEffectHidden(true, for: .all)
    }

    /// A tap inserts and hands the person back to the keyboard they type with; a long press inserts and stays, for a
    /// second clip. iOS offers only "the next keyboard", which is the person's own when Pesto was added last.
    private func insert(_ entry: QuickInsertEntry, thenSwitch: Bool) {
        keys.insert(entry.insertionText())
        if thenSwitch {
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
