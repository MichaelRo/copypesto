// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData
import SwiftUI

/// The collections in Settings: a list to reorder and edit, and the collections Pesto suggests. The pane header holds
/// the buttons that add one and ask for suggestions, which reach this view as counters.
struct CollectionListView: View {
    nonisolated static let suggestionCandidateLimit = 200

    /// The newest clips: all the suggestions look at, so a long history is not loaded into a settings list.
    nonisolated static var candidatesDescriptor: FetchDescriptor<ClipboardItem> {
        var descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = suggestionCandidateLimit
        return descriptor
    }

    @Environment(\.pestoAccent) private var accent
    @Query(sort: \Pinboard.sortOrder) private var pinboards: [Pinboard]
    @Query(CollectionListView.candidatesDescriptor) private var items: [ClipboardItem]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState
    @State private var showingEditor = false
    @State private var editing: Pinboard?
    @State private var suggestions: [CollectionSuggestion] = []
    @AppStorage(Setting.dismissedCollectionSuggestions) private var dismissedRaw: String
    let addRequest: Int
    let importRequest: Int

    var body: some View {
        Form {
            Section {
                if pinboards.isEmpty {
                    Text("No collections yet. Add one, or let Pesto suggest some from what you copy.")
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                ForEach(pinboards) { pinboard in
                    row(pinboard)
                }
                .onMove(perform: move)
            } header: {
                Text("Your collections")
            } footer: {
                Text("Drag to reorder. They appear on the shelf in this order.").pestoCaption()
            }

            ForEach(CollectionSuggestion.Group.allCases, id: \.self) { group in
                let rows = suggestions.filter { $0.group == group }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { suggestionRow($0) }
                    } header: {
                        Text(group.title)
                    } footer: {
                        Text(group.caption).pestoCaption()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { computeSuggestions() }
        .onChange(of: addRequest) {
            editing = nil
            showingEditor = true
        }
        .onChange(of: importRequest) {
            importCollection()
        }
        .sheet(isPresented: $showingEditor) {
            CollectionEditor(existing: editing) { name, symbol, color, triggerBundleID, isSmart, predicateData in
                save(
                    name: name, symbol: symbol, color: color,
                    triggerBundleID: triggerBundleID, isSmart: isSmart, predicateData: predicateData
                )
            } onDelete: {
                guard let board = editing else { return }
                appState.deleteCollection(id: board.id, fromShelf: false)
            }
        }
    }

    // MARK: - Smart collections

    private func row(_ pinboard: Pinboard) -> some View {
        let tint = Color(hex: pinboard.colorHex) ?? accent
        return Button {
            editing = pinboard
            showingEditor = true
        } label: {
            HStack(spacing: 12) {
                CollectionIcon(symbolName: pinboard.symbolName)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pinboard.name)
                    if let bid = pinboard.triggerBundleID {
                        Text(runningAppName(for: bid) ?? bid).pestoCaption()
                    }
                }
                Spacer()
                if pinboard.isSmart {
                    Image(systemName: "sparkles").foregroundStyle(accent).accessibilityLabel("Smart collection")
                }
                Image(systemName: "chevron.right").font(.caption).pestoQuiet().accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Export Collection\u{2026}", systemImage: "square.and.arrow.up") {
                appState.exportCollection?(pinboard.id)
            }
        }
        .accessibilityHint("Opens the collection to edit")
    }

    private var dismissed: Set<String> {
        Set(dismissedRaw.split(separator: "\n").map(String.init))
    }

    private func suggestionRow(_ suggestion: CollectionSuggestion) -> some View {
        let tint = Color(hex: suggestion.colorHex) ?? accent
        return HStack(spacing: 12) {
            CollectionIcon(symbolName: suggestion.symbol)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(suggestion.name)
                    Text("Smart")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(accent.opacity(0.16)))
                        .foregroundStyle(.primary)
                        .help("A smart collection fills itself from a rule. Nothing moves out of where it is.")
                }
                if let count = suggestion.matchCount {
                    Text("\(count) clips match").pestoCaption()
                } else if let blurb = suggestion.blurb {
                    Text(blurb).pestoCaption()
                }
            }
            Spacer()
            Button("Add") { createCollection(from: suggestion) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier(AccessibilityID.addSuggestedCollection(suggestion.id))
            Button {
                dismiss(suggestion)
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .pestoQuiet()
            .accessibilityLabel("Dismiss \(suggestion.name)")
            .help("Do not suggest this again")
        }
        .accessibilityElement(children: .contain)
    }

    private func computeSuggestions() {
        let candidates = items.compactMap { item -> SmartCollectionSuggestions.ItemInput? in
            guard let data = item.embeddingData else { return nil }
            return SmartCollectionSuggestions.ItemInput(id: item.id, preview: item.displayPreviewText, embedding: data)
        }
        let existing = pinboards.compactMap { board in
            board.isSmart ? board.smartPredicateData.flatMap { try? SmartCollectionPredicate.decodeRuleSet($0) } : nil
        }
        Task {
            let topics = await SmartCollectionSuggestions.shared.suggest(items: candidates)
            suggestions = CollectionSuggester.suggest(
                clips: items, id: \.id, existing: existing, topics: topics, dismissed: dismissed
            )
        }
    }

    /// A suggestion is always a smart collection: it fills itself from a rule, so creating one never moves a clip out
    /// of
    /// the collection it is in.
    private func createCollection(from suggestion: CollectionSuggestion) {
        guard let data = try? SmartCollectionPredicate.encodeRuleSet(suggestion.ruleSet) else { return }
        let next = (pinboards.map(\.sortOrder).max() ?? -1) + 1
        let board = Pinboard(
            name: CollectionNaming.uniqueName(suggestion.name, existing: pinboards.map(\.name)),
            symbolName: suggestion.symbol,
            colorHex: suggestion.colorHex,
            sortOrder: next,
            isSmart: true,
            smartPredicateData: data,
            triggerBundleID: nil
        )
        appState.attempt("Couldn\u{2019}t add the collection") {
            try appState.collectionStore(context: modelContext).insert(.create, [board])
        }
        suggestions.removeAll { $0.id == suggestion.id }
    }

    private func dismiss(_ suggestion: CollectionSuggestion) {
        dismissedRaw = (dismissed.union([suggestion.id])).sorted().joined(separator: "\n")
        suggestions.removeAll { $0.id == suggestion.id }
    }

    // MARK: - Standard CRUD

    // swiftlint:disable:next function_parameter_count
    private func save(
        name: String, symbol: String, color: String,
        triggerBundleID: String?, isSmart: Bool, predicateData: Data?
    ) {
        let name = CollectionNaming.uniqueName(name, existing: pinboards.map(\.name), excluding: editing?.name)
        let store = appState.collectionStore(context: modelContext)
        appState.attempt("Couldn\u{2019}t save the collection") {
            if let p = editing {
                try store.edit(.edit, [p]) {
                    p.name = name
                    p.symbolName = symbol
                    p.colorHex = color
                    p.triggerBundleID = triggerBundleID
                    p.isSmart = isSmart
                    p.smartPredicateData = predicateData
                }
            } else {
                let next = (pinboards.map(\.sortOrder).max() ?? -1) + 1
                try store.insert(.create, [Pinboard(
                    name: name,
                    symbolName: symbol,
                    colorHex: color,
                    sortOrder: next,
                    isSmart: isSmart,
                    smartPredicateData: predicateData,
                    triggerBundleID: triggerBundleID
                )])
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = pinboards
        reordered.move(fromOffsets: source, toOffset: destination)
        appState.attempt("Couldn\u{2019}t save the collection order") {
            try appState.collectionStore(context: modelContext).edit(.reorder, reordered) {
                for (i, p) in reordered.enumerated() {
                    p.sortOrder = i
                }
            }
        }
    }

    private func runningAppName(for bundleID: String) -> String? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .localizedName
    }

    private func importCollection() {
        guard let container = appState.historyContainer else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let undoHistory = appState.undoHistory
        Task {
            await appState.attempt("Couldn\u{2019}t import the collection") {
                _ = try await HistoryExporter(modelContainer: container)
                    .importCollection(fromFile: url, undoHistory: undoHistory)
            }
        }
    }
}
