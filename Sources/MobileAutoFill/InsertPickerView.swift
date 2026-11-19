// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The list AutoFill shows when the person asks Pesto for text: Pinned, Snippets and Recent, with a search.
struct InsertPickerView: View {
    let menu: QuickInsertMenu
    let insert: (QuickInsertEntry) -> Void
    let cancel: () -> Void
    @State private var query = ""

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
        .tint(BrandAccent.color)
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
                Section(Self.title(of: group.section)) {
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
        Button { insert(entry) } label: {
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
        }
    }
}
