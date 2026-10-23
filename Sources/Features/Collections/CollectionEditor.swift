// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftUI

/// Sheet for creating or editing a Collection (the Swift type is `Pinboard` for SwiftData entity-name continuity).
struct CollectionEditor: View {
    @Environment(\.pestoAccent) private var accent
    var existing: Pinboard?
    /// Called on Save with (name, symbolName, colorHex, triggerBundleID, isSmart, smartPredicateData).
    var onSave: ((String, String, String, String?, Bool, Data?) -> Void)?
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var confirmingDelete = false
    @State private var symbolName = "tray.full"
    @State private var colorHex = "007AFF"
    @State private var triggerBundleID: String?
    @State private var useEmoji = false
    @State private var emojiText = ""
    @State private var showEmojiPicker = false
    @State private var isSmart = false
    @State private var ruleSet = PredicateRuleSet(
        combinator: .and,
        groups: [PredicateRuleSet.Group(combinator: .and, rules: [
            PredicateRule(field: .type, op: .equals, value: .string("text"))
        ])]
    )

    /// Regular-policy apps currently running, excluding Pesto itself.
    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
                $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
                $0.bundleIdentifier != nil
        }
        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Collection name", text: $name)
                }

                Section("Kind") {
                    Picker("Kind", selection: $isSmart) {
                        Text("Static").tag(false)
                        Text("Smart").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if isSmart {
                        starterTemplatesRow
                        SmartCollectionBuilder(ruleSet: $ruleSet)
                            .padding(.vertical, 4)
                    }
                }

                Section("Icon") {
                    Picker("Style", selection: $useEmoji) {
                        Text("Symbol").tag(false)
                        Text("Emoji").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if useEmoji {
                        HStack(spacing: 12) {
                            Button {
                                showEmojiPicker.toggle()
                            } label: {
                                Group {
                                    if emojiText.isEmpty {
                                        Image(systemName: "face.smiling")
                                            .font(.system(size: 28))
                                            .pestoQuiet()
                                    } else {
                                        Text(emojiText)
                                            .font(.system(size: 28))
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showEmojiPicker, arrowEdge: .bottom) {
                                EmojiPickerPopover(
                                    name: name,
                                    selectedEmoji: emojiText.isEmpty ? nil : emojiText
                                ) { picked in
                                    emojiText = picked
                                    symbolName = picked
                                    showEmojiPicker = false
                                } onOpenSystem: {
                                    showEmojiPicker = false
                                    NSApp.orderFrontCharacterPalette(nil)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(emojiText.isEmpty ? "Choose an emoji" : emojiText.isEmpty ? "" : "Selected")
                                    .scaledFont(size: 12, weight: .medium)
                                Button("Browse Emojis…") {
                                    NSApp.orderFrontCharacterPalette(nil)
                                }
                                .scaledFont(size: 11)
                                .foregroundStyle(accent)
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        CollectionIconPicker(selection: $symbolName)
                    }
                }

                Section("Color") {
                    CollectionColorRow(colorHex: $colorHex, diameter: 24, spacing: 8)
                }

                if !isSmart {
                    Section {
                        triggerAppPicker
                    } header: {
                        Text("Trigger app")
                    } footer: {
                        Text("Pesto auto-selects this collection when the chosen app becomes frontmost.")
                            .pestoQuiet()
                    }
                }

                if existing != nil {
                    Section {
                        Button("Delete Collection", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .confirmationDialog("Delete this collection?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Collection", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The clips in it stay in your history.")
            }
            .navigationTitle(existing == nil ? "New Collection" : "Edit Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let predicateData = isSmart ? (try? SmartCollectionPredicate.encodeRuleSet(ruleSet)) : nil
                        onSave?(name, symbolName, colorHex, isSmart ? nil : triggerBundleID, isSmart, predicateData)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let p = existing {
                    name = p.name
                    colorHex = p.colorHex
                    isSmart = p.isSmart
                    triggerBundleID = p.triggerBundleID
                    let isEmoji = p.symbolName.unicodeScalars.first.map {
                        $0.properties.isEmoji && $0.value > 0x238C
                    } ?? false
                    if isEmoji {
                        useEmoji = true
                        emojiText = p.symbolName
                        symbolName = p.symbolName
                    } else {
                        useEmoji = false
                        symbolName = p.symbolName
                    }
                    // Load existing rule set (migrating v1 if needed).
                    if p.isSmart, let data = p.smartPredicateData,
                       let loaded = try? SmartCollectionPredicate.decodeRuleSet(data)
                    {
                        ruleSet = loaded
                    }
                }
            }
        }
        .frame(width: 420, height: isSmart ? 620 : 520)
    }

    private var triggerAppPicker: some View {
        Menu {
            Button("None") { triggerBundleID = nil }
            Divider()
            ForEach(runningApps, id: \.bundleIdentifier) { app in
                Button {
                    triggerBundleID = app.bundleIdentifier
                } label: {
                    if let icon = app.icon {
                        Label {
                            Text(app.localizedName ?? app.bundleIdentifier ?? "")
                        } icon: {
                            Image(nsImage: icon)
                        }
                    } else {
                        Text(app.localizedName ?? app.bundleIdentifier ?? "")
                    }
                }
            }
        } label: {
            if let bid = triggerBundleID,
               let app = runningApps.first(where: { $0.bundleIdentifier == bid })
            {
                Label(app.localizedName ?? bid, systemImage: "app.badge")
            } else if let bid = triggerBundleID {
                Label(bid, systemImage: "app.badge")
            } else {
                Label("None", systemImage: "minus.circle")
                    .pestoQuiet()
            }
        }
    }

    private var starterTemplatesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CollectionSuggester.starters()) { starter in
                    Button {
                        if name.isEmpty {
                            name = starter.name
                        }
                        symbolName = starter.symbol
                        colorHex = starter.colorHex
                        ruleSet = starter.ruleSet
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: starter.symbol)
                            Text(starter.name)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
