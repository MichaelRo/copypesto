// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The list AutoFill shows when the person asks Pesto for text: Pinned, Snippets and Recent, with a search.
struct InsertPickerView: View {
    let menu: QuickInsertMenu
    let insert: (QuickInsertEntry) -> Void
    var insertText: ((String) -> Void)?
    let cancel: () -> Void
    @State private var query = ""
    @State private var pendingFill: PendingSnippetFill?
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedAccent: Color {
        menu.accent.flatMap { Color(hex: $0.accent(dark: colorScheme == .dark)) } ?? BrandAccent.color
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
                description: Text("In Pesto, open Settings and turn on Insert from Pesto in other apps.")
            )
        case .empty:
            ContentUnavailableView(
                "No Text Clips",
                systemImage: "text.insert",
                description: Text("Your pinned and recent text clips appear here. Clips with secrets never do.")
            )
        case .ready:
            list
        }
    }

    private var list: some View {
        let groups = menu.groups(matching: query)
        return List {
            ForEach(groups) { group in
                Section(group.collection?.name ?? Self.title(of: group.section)) {
                    ForEach(group.entries) { entry in
                        row(entry)
                    }
                }
            }
        }
        .overlay {
            if groups.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
    }

    private func row(_ entry: QuickInsertEntry) -> some View {
        Button { choose(entry) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label())
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detail = Self.detail(of: entry) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityLabel(entry.label())
        .accessibilityValue(Self.detail(of: entry) ?? "")
        .accessibilityHint("Inserts this clip")
    }

    private static func detail(of entry: QuickInsertEntry) -> String? {
        let line = entry.text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty && $0 != entry.title }
        return line.map { String($0.prefix(QuickInsertPolicy.maxTitleCharacters)) }
    }

    private static func title(of section: QuickInsertEntry.Section) -> String {
        switch section {
        case .pinned: String(localized: "Pinned")
        case .snippets: String(localized: "Snippets")
        case .recent: String(localized: "Recent")
        case .collection: String(localized: "Collections")
        }
    }

    private func choose(_ entry: QuickInsertEntry) {
        if insertText != nil,
           let plan = SnippetCopyPlan.plan(for: entry.text, isSnippet: entry.section == .snippets),
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

    init(fill: PendingSnippetFill, onInsert: @escaping (String) -> Void) {
        self.fill = fill
        self.onInsert = onInsert
        _fills = State(initialValue: SnippetFills.initial(for: fill.plan.fields))
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(fill.plan.fields) { field in
                    Section(field.label) {
                        switch field.kind {
                        case let .text(multiline):
                            TextField(
                                field.defaultValue ?? field.label,
                                text: Binding(
                                    get: { fills.values[field.id] ?? "" },
                                    set: { fills.values[field.id] = $0 }
                                ),
                                axis: multiline ? .vertical : .horizontal
                            )
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
            .navigationTitle(fill.entry.label())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        let expanded = fill.plan.expanded(
                            fill.entry.text, fills: fills, pastedClipboard: "", at: .now
                        )
                        onInsert(expanded)
                    }
                }
            }
        }
    }
}
