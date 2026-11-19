// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The search page (ADR 0063): Pesto's own search field, the matching clips in one row, and letters (or numbers) that
/// type into that field only. Picking a clip is the one thing that reaches the app, through `pick`.
struct KeyboardSearchPage: View {
    let model: KeyboardModel
    weak var controller: UIInputViewController?
    let pick: (QuickInsertEntry, _ longPress: Bool) -> Void
    let close: () -> Void

    @State private var showsDigits = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var query: KeyboardQuery {
        model.searchQuery ?? KeyboardQuery()
    }

    private var results: [QuickInsertEntry] {
        if let search = query.search { return model.menu.entries(matching: search) }
        return model.menu.chips.first.map { model.menu.entries(for: $0.chip) } ?? []
    }

    var body: some View {
        VStack(spacing: 6) {
            field
            resultRow
                .frame(height: 58)
            if showsDigits {
                KeyboardPad(insert: model.typeInSearch)
            } else {
                KeyboardLetters(type: model.typeInSearch)
            }
            bottomRow
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Group {
                if query.text.isEmpty {
                    Text("Search your clips").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: query.text).foregroundStyle(.primary)
                }
            }
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !query.text.isEmpty {
                Button(action: model.clearSearch) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear Search"))
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isSearchField)
    }

    @ViewBuilder
    private var resultRow: some View {
        if results.isEmpty {
            Text("No clips match.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(results) { entry in
                        KeyboardClipKey(entry: entry, isInserted: false)
                            .frame(width: sizeClass == .regular ? 180 : 150)
                            .onTapGesture { pick(entry, false) }
                            .onLongPressGesture(minimumDuration: 0.4) { pick(entry, true) }
                            .accessibilityAction { pick(entry, false) }
                    }
                }
            }
            .scrollEdgeEffectHidden(true, for: .all)
            .id(query.search ?? "")
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if model.showsGlobeKey {
                GlobeKey(controller: controller)
                    .frame(width: 44, height: 40)
            }
            Button { showsDigits.toggle() } label: {
                Text(verbatim: showsDigits ? "ABC" : "123").frame(width: 52, height: 40)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(showsDigits ? Text("Letters") : Text("Numbers"))
            Button { model.typeInSearch(" ") } label: {
                Text("Space").frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
            Button(action: model.deleteInSearch) {
                Image(systemName: "delete.left").frame(width: 44, height: 40)
            }
            .buttonStyle(.bordered)
            .buttonRepeatBehavior(.enabled)
            .accessibilityLabel(Text("Delete"))
            Button(action: close) {
                Text("Done").fontWeight(.semibold).frame(width: 64, height: 40)
            }
            .buttonStyle(KeyboardKeyStyle(isAccent: true))
        }
        .font(.body)
        .tint(.primary)
    }
}
