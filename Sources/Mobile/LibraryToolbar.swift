// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct LibraryToolbar: ToolbarContent {
    let showsSettings: Bool
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library

    var body: some ToolbarContent {
        if showsSettings {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { library.showsSettings = true }
                    .accessibilityIdentifier(MobileAccessibilityID.settingsButton)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("New Note", systemImage: "square.and.pencil") { library.isComposing = true }
                .accessibilityIdentifier(MobileAccessibilityID.newNoteButton)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            PasteButton(supportedContentTypes: ItemProviderCapture.acceptedTypes) { providers in
                Task { await appState.add(from: providers, method: .paste) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

enum LibraryTitle {
    static func text(for scope: LibraryScope, collections: [Pinboard]) -> String {
        switch scope {
        case .all: "Pesto"
        case .pinned: scope.title
        case let .collection(id): collections.first { $0.id == id }?.name ?? scope.title
        }
    }
}
