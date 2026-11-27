// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The list AutoFill shows when the person asks Pesto for text: Pinned, Snippets and Recent, with a search.
struct InsertPickerView: View {
    let menu: QuickInsertMenu
    let insert: (QuickInsertEntry) -> Void
    var insertText: ((String) -> Void)?
    let cancel: () -> Void
    var unlock: (() -> Void)?
    @State private var query = ""
    @State private var activeChip: QuickInsertMenu.Chip = .all
    @State private var pendingFill: PendingSnippetFill?
    @State private var rowWidth: CGFloat = 360
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var theme: WidgetSnapshot.Theme {
        menu.accent ?? .brand
    }

    private var resolvedAccent: Color {
        Color(hex: theme.accent(dark: colorScheme == .dark)) ?? BrandAccent.color
    }

    private var resolvedAccentLabel: Color {
        let hex = theme.accent(dark: colorScheme == .dark)
        return Color(hex: ContrastRatio.labelHex(onFill: hex)) ?? .white
    }

    private var ground: Color {
        Color(hex: theme.ground(dark: colorScheme == .dark))
            ?? Color(uiColor: .systemGroupedBackground)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Insert from Pesto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                    }
                }
        }
        .tint(resolvedAccent)
        .environment(\.pestoAccent, resolvedAccent)
        .environment(\.pestoAccentLabel, resolvedAccentLabel)
        .environment(\.pestoSurface, ground)
        .sheet(item: $pendingFill) { fill in
            AutoFillSnippetSheet(fill: fill) { expanded in
                pendingFill = nil
                if let insertText {
                    insertText(expanded)
                } else {
                    insert(fill.entry)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch menu.state {
        case .unavailable:
            ContentUnavailableView(
                "Nothing to Insert Yet",
                systemImage: "text.insert",
                description: Text("Open Pesto once so your clips are ready here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ground.ignoresSafeArea())
        case .locked:
            ContentUnavailableView {
                Label("Pesto is Locked", systemImage: "lock.fill")
            } description: {
                Text("Open Pesto and unlock to insert clips.")
            } actions: {
                if let unlock {
                    Button("Unlock in Pesto", systemImage: "lock.open", action: unlock)
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ground.ignoresSafeArea())
        case .empty:
            ContentUnavailableView(
                "No Text Clips",
                systemImage: "text.insert",
                description: Text("Your pinned and recent text clips appear here. Clips with secrets never do.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ground.ignoresSafeArea())
        case .ready:
            grid
        }
    }

    private var grid: some View {
        let groups = menu.groups(matching: query, chip: activeChip)
        let columnsCount = CardGridLayout.columnCount(
            width: rowWidth, isAccessibilitySize: typeSize.isAccessibilitySize
        )
        let cardWidth = CardGridLayout.cardWidth(rowWidth: rowWidth, columns: columnsCount)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: CardGridLayout.spacing, alignment: .top),
            count: columnsCount
        )
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: columns, spacing: CardGridLayout.spacing) {
                            ForEach(group.entries) { entry in
                                cardButton(entry, width: cardWidth)
                            }
                        }
                        .padding(.horizontal, CardGridLayout.margin)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .onGeometryChange(for: CGFloat.self) { max(0, $0.size.width - CardGridLayout.margin * 2) } action: {
            rowWidth = $0
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if menu.chips.count > 1 {
                chipBar
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("Clips only, never passwords")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(ground.opacity(0.92))
        }
        .background(ground.ignoresSafeArea())
        .overlay {
            if groups.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
    }

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(menu.chips, id: \.chip) { label in
                    let isActive = activeChip == label.chip
                    Button {
                        activeChip = label.chip
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: label.symbolName)
                                .font(.caption)
                            Text(label.title)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(MobileChipStyle(
                        isActive: isActive,
                        tint: label.color.isEmpty ? nil : Color(hex: label.color),
                        chipHeight: 30,
                        touchMinimum: 36
                    ))
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal, CardGridLayout.margin)
            .padding(.vertical, 8)
        }
        .background(ground.opacity(0.95))
    }

    private func cardButton(_ entry: QuickInsertEntry, width: CGFloat) -> some View {
        let isFillIn = needsFillIn(entry)
        return Button { choose(entry) } label: {
            QuickInsertCardFace(
                entry: entry,
                size: CGSize(width: width, height: (width / CardGridLayout.aspectRatio).rounded()),
                theme: theme,
                appIcon: menu.appIcon(for: entry),
                inCollection: activeChip != .all && entry.section == .collection,
                hasShadow: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.label())
        .accessibilityValue(Self.detail(of: entry) ?? "")
        .accessibilityHint(isFillIn ? "Opens snippet fill-in" : "Inserts this clip")
    }

    private func needsFillIn(_ entry: QuickInsertEntry) -> Bool {
        insertText != nil
            && entry.expandsOnInsert
            && !TemplateExpander.fillsWithoutAsking(entry.text)
    }

    private static func detail(of entry: QuickInsertEntry) -> String? {
        let line = entry.text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty && $0 != entry.title }
        return line.map { String($0.prefix(QuickInsertPolicy.maxTitleCharacters)) }
    }

    private func choose(_ entry: QuickInsertEntry) {
        if insertText != nil,
           let plan = SnippetCopyPlan.plan(for: entry.text, isSnippet: entry.expandsOnInsert),
           plan.needsSheet
        {
            pendingFill = PendingSnippetFill(entry: entry, plan: plan)
            return
        }
        insert(entry)
    }
}

private struct PendingSnippetFill: Identifiable {
    let entry: QuickInsertEntry
    let plan: SnippetCopyPlan
    var id: UUID {
        entry.id
    }
}

private struct AutoFillSnippetSheet: View {
    let fill: PendingSnippetFill
    let onInsert: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fills: SnippetFills
    @FocusState private var focusedFieldID: String?

    init(fill: PendingSnippetFill, onInsert: @escaping (String) -> Void) {
        self.fill = fill
        self.onInsert = onInsert
        _fills = State(initialValue: SnippetFills.initial(
            for: fill.plan.fields,
            remembered: fill.entry.fieldMemory ?? [:]
        ))
    }

    private var textFieldIDs: [String] {
        fill.plan.fields.compactMap {
            if case .text = $0.kind { return $0.id }
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(fill.plan.fields) { field in
                        switch field.kind {
                        case let .text(multiline):
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                TextField(
                                    field.defaultValue ?? field.label,
                                    text: Binding(
                                        get: { fills.values[field.id] ?? "" },
                                        set: { fills.values[field.id] = $0 }
                                    ),
                                    axis: multiline ? .vertical : .horizontal
                                )
                                .lineLimit(multiline ? 1...6 : 1...1)
                                .accessibilityLabel(field.label)
                                .focused($focusedFieldID, equals: field.id)
                                .submitLabel(multiline ? .return : .done)
                                .onSubmit {
                                    guard !multiline else { return }
                                    insertExpanded()
                                }
                            }
                        case let .choice(choices):
                            Picker(field.label, selection: Binding(
                                get: { fills.values[field.id] ?? choices.first ?? "" },
                                set: { fills.values[field.id] = $0 }
                            )) {
                                ForEach(choices, id: \.self) { choice in
                                    Text(choice).tag(choice)
                                }
                            }
                        case .optional:
                            Toggle(field.label, isOn: Binding(
                                get: { fills.included.contains(field.id) },
                                set: { included in
                                    if included {
                                        fills.included.insert(field.id)
                                    } else {
                                        fills.included.remove(field.id)
                                    }
                                }
                            ))
                        }
                    }
                }
            }
            .onAppear {
                focusedFieldID = textFieldIDs.first
            }
            .navigationTitle(fill.entry.label())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert", action: insertExpanded)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }

    private func insertExpanded() {
        let expanded = fill.plan.expanded(
            fill.entry.text, fills: fills, pastedClipboard: "", at: .now
        )
        onInsert(expanded)
    }
}
