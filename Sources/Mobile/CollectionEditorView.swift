// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

/// New Collection and Edit Collection: a name, an icon and a color, saved through `CollectionStore` as one undoable
/// change.
struct CollectionEditorView: View {
    let board: Pinboard?

    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pestoAccent) private var accent
    @Environment(\.pestoSurface) private var ground
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var draft: CollectionDraft?
    @State private var exportedShare: ClipShare?
    @State private var isExporting = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let draft = Binding($draft) {
                    Section {
                        TextField("Name", text: draft.name)
                            .focused($nameFocused)
                            .accessibilityIdentifier(MobileAccessibilityID.collectionNameField)
                        if board == nil {
                            Picker("Kind", selection: draft.isSmart) {
                                Text("Plain").tag(false)
                                Text("Smart").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier(MobileAccessibilityID.collectionKindPicker)
                        }
                    } footer: {
                        if board == nil {
                            Text("A plain collection holds the clips you add. A smart one fills itself from rules.")
                        }
                    }
                    rulesSections(draft)
                    Section("Icon") { symbolGrid(draft) }
                    Section("Color") { colorRow(draft) }
                    if let board, !board.isSmart {
                        Section {
                            Button("Export Collection\u{2026}", systemImage: "square.and.arrow.up") {
                                export(board)
                            }
                            .disabled(isExporting)
                        } footer: {
                            Text("Saves clips in this collection as a .pesto file you can share or import elsewhere.")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ground.ignoresSafeArea())
            .navigationTitle(board == nil ? "New Collection" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) { LibraryBanners(messagesOnly: true) }
            .sheet(item: $exportedShare) { share in
                ShareSheet(items: share.items, files: share.files).presentationDetents([.medium, .large])
            }
            .onDisappear {
                exportedShare?.files.forEach(ShareFile.remove)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(board == nil ? "Add" : "Save") { save() }
                        .disabled(draft?.canSave == false)
                        .accessibilityIdentifier(MobileAccessibilityID.saveCollectionButton)
                }
            }
        }
        .onAppear {
            guard draft == nil else { return }
            draft = board.map(CollectionDraft.init) ?? .new(existing: collections)
            if board == nil { nameFocused = true }
        }
    }

    @ViewBuilder
    private func rulesSections(_ draft: Binding<CollectionDraft>) -> some View {
        if draft.wrappedValue.isSmart {
            if let rules = Binding(draft.rules) {
                SmartRulesEditor(draft: rules)
            } else {
                Section {
                    Text("These rules were made by a newer version of Pesto, so they can\u{2019}t be edited here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func symbolGrid(_ draft: Binding<CollectionDraft>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            ForEach(draft.wrappedValue.symbolChoices, id: \.self) { symbol in
                let chosen = draft.wrappedValue.symbol == symbol
                Button {
                    draft.wrappedValue.symbol = symbol
                } label: {
                    CollectionIcon(symbol: symbol)
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(chosen ? (Color(hex: draft.wrappedValue.colorHex) ?? accent) : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(chosen ? (Color(hex: draft.wrappedValue.colorHex) ?? accent)
                                    .opacity(0.18) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(chosen ? (Color(hex: draft.wrappedValue.colorHex) ?? accent) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CollectionSymbols.name(for: symbol))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier(MobileAccessibilityID.collectionIconPicker)
    }

    private func colorRow(_ draft: Binding<CollectionDraft>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: TouchTarget.minimum), spacing: 0)], spacing: 0) {
            ForEach(draft.wrappedValue.colorChoices, id: \.self) { hex in
                let chosen = CollectionPalette.isSame(draft.wrappedValue.colorHex, hex)
                Button {
                    draft.wrappedValue.colorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? .secondary)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if chosen {
                                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay(Circle().strokeBorder(chosen ? Color.primary.opacity(0.4) : .clear, lineWidth: 1.5))
                        .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CollectionPalette.name(forHex: hex))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        guard let draft else { return }
        if let board {
            appState.updateCollection(board, to: draft, existing: collections)
        } else if let added = appState.addCollection(draft, existing: collections) {
            library.filter.choose(.collection(added.id))
        }
        dismiss()
    }

    private func export(_ board: Pinboard) {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            if let url = await appState.exportCollection(board) {
                exportedShare = ClipShare(file: url)
            }
        }
    }
}
