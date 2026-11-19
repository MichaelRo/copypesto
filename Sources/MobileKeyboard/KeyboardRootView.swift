// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI
import UIKit

/// The keyboard: the starters, then the clips by section (no search field, since this keyboard is the one typing),
/// then a row of Space, Return and Delete so a quick edit needs no switch.
struct KeyboardRootView: View {
    let model: KeyboardModel
    let keys: KeyboardKeys
    weak var controller: UIInputViewController?

    @State private var filter = KeyboardMenu.Filter.all
    @State private var inserted: UUID?
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 8) {
            starterRow
            if !model.menu.filters.isEmpty { filterRow }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .tint(BrandAccent.color)
        .onChange(of: model.menu) {
            if !model.menu.filters.contains(filter) { filter = .all }
        }
    }

    private var starterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.menu.starters) { starter in
                    Button(starter.title) { keys.insert(starter.text()) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .font(.subheadline)
                        // A UUID is new at the tap, so reading one out would name a different value.
                        .accessibilityValue(starter == .uuid ? Text(verbatim: "") : Text(starter.text()))
                        .accessibilityHint(Text("Inserts it now"))
                }
            }
        }
        // iOS 26's soft edge blurred the whole row: it is shorter than the edge effect.
        .scrollEdgeEffectHidden(true, for: .all)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var filterRow: some View {
        Picker("Show", selection: $filter) {
            ForEach(model.menu.filters) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        switch model.menu.state {
        case .restricted:
            note(
                "Allow Full Access to Insert Your Clips",
                """
                Turn it on in Settings > General > Keyboard > Keyboards > Pesto. The keyboard has no network access, \
                and the keys above work without it.
                """
            )
        case .unavailable:
            note("Nothing to Insert Yet", "In Pesto, open Settings and turn on Insert from Pesto in other apps.")
        case .empty:
            note(
                "No Text Clips",
                """
                Your pinned and recent text clips appear here. Clips with secrets never do, and while the History \
                Lock is on none do unless you allow it in Pesto's Settings.
                """
            )
        case .ready:
            grid
        }
    }

    private func note(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: sizeClass == .regular ? 3 : 2)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.menu.entries(for: filter)) { entry in
                    clipKey(entry)
                }
            }
        }
    }

    private func clipKey(_ entry: QuickInsertEntry) -> some View {
        Button {
            keys.insert(entry.insertionText())
            inserted = entry.id
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                if inserted == entry.id { inserted = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Text(entry.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if inserted == entry.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(BrandAccent.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.title)
        .accessibilityHint(Text("Inserts this clip"))
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if model.showsGlobeKey {
                GlobeKey(controller: controller)
                    .frame(width: 44, height: 40)
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
}
