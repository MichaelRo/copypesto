// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI

struct LibraryEmptyState: View {
    let isEmpty: Bool
    let hasClips: Bool
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]

    var body: some View {
        if isEmpty {
            let trimmed = library.query.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            } else if !hasClips {
                ContentUnavailableView {
                    Label("No Clips Yet", systemImage: "doc.on.clipboard")
                } description: {
                    Text("Paste what you copied to keep it here, or write a new note.")
                } actions: {
                    PasteButton(supportedContentTypes: ItemProviderCapture.acceptedTypes) { providers in
                        Task { await appState.add(from: providers, method: .paste) }
                    }
                }
            } else if isSnippetsScope {
                ContentUnavailableView {
                    Label("No Snippets Yet", systemImage: "curlybraces")
                } description: {
                    Text("Create a snippet with fill-ins, or save a clip as a snippet from its menu.")
                } actions: {
                    Button("New Snippet\u{2026}", systemImage: "curlybraces") {
                        library.beginNewSnippet()
                    }
                    .buttonStyle(.pestoProminent)
                    .accessibilityIdentifier(MobileAccessibilityID.newSnippetButton)
                }
            } else {
                ContentUnavailableView("Nothing Here", systemImage: "tray", description: Text(scopeText))
            }
        }
    }

    private var isSnippetsScope: Bool {
        guard case let .collection(id) = library.filter.scope else { return false }
        if id == PredicateRuleSet.snippetsCollectionID { return true }
        guard let board = collections.first(where: { $0.id == id }), board.isSmart,
              let data = board.smartPredicateData,
              let ruleSet = try? SmartCollectionPredicate.decodeRuleSet(data) else { return false }
        return ruleSet == PredicateRuleSet.snippets
    }

    private var scopeText: String {
        if library.isSearching, !library.filter.kinds.isEmpty {
            return String(localized: "No clip of this kind matches.")
        }
        return switch library.filter.scope {
        case .pinned: String(localized: "Pin a clip to keep it here for good.")
        case .collection: String(localized: "Add a clip to this collection from its menu.")
        case .all: String(localized: "Nothing matches.")
        }
    }
}
