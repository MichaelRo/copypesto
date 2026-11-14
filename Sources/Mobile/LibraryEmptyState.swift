// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct LibraryEmptyState: View {
    let isEmpty: Bool
    let hasClips: Bool
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library

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
                        Task { await appState.add(from: providers) }
                    }
                }
            } else {
                ContentUnavailableView("Nothing Here", systemImage: "tray", description: Text(scopeText))
            }
        }
    }

    private var scopeText: String {
        if library.isSearching, library.filter.kind != nil {
            return String(localized: "No clip of this kind matches.")
        }
        return switch library.filter.scope {
        case .pinned: String(localized: "Pin a clip to keep it here for good.")
        case .collection: String(localized: "Add a clip to this collection from its menu.")
        case .all: String(localized: "Nothing matches.")
        }
    }
}
