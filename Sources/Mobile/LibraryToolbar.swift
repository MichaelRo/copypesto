// SPDX-License-Identifier: MIT
import PestoCore
import SwiftData
import SwiftUI
import UIKit

struct LibraryToolbar: ToolbarContent {
    let showsSettings: Bool
    @Environment(MobileAppState.self) private var appState
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Pinboard.sortOrder) private var collections: [Pinboard]
    @State private var hasClipboardContent = Self.clipboardHasContent()

    private var targetCollectionID: UUID? {
        library.targetCollectionID(in: collections)
    }

    var body: some ToolbarContent {
        if showsSettings {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { library.showsSettings = true }
                    .accessibilityIdentifier(MobileAccessibilityID.settingsButton)
            }
        }
        if library.isSelecting {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { library.endSelection() }
                    .bold()
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button("Select Clips", systemImage: "checkmark.circle") {
                    library.beginSelection()
                }
                .accessibilityIdentifier(MobileAccessibilityID.selectClipsButton)
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button("New Clip", systemImage: "plus") { library.isComposing = true }
                    .accessibilityIdentifier(MobileAccessibilityID.newNoteButton)
            }
            if hasClipboardContent {
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    PasteButton(supportedContentTypes: ItemProviderCapture.acceptedTypes) { providers in
                        let destination = targetCollectionID
                        Task { await appState.add(from: providers, method: .paste, into: destination) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .onAppear { hasClipboardContent = Self.clipboardHasContent() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { hasClipboardContent = Self.clipboardHasContent() }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
                        hasClipboardContent = Self.clipboardHasContent()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.removedNotification)) { _ in
                        hasClipboardContent = Self.clipboardHasContent()
                    }
                }
            } else {
                ToolbarItem(placement: .status) {
                    Color.clear.frame(width: 0, height: 0)
                        .onAppear { hasClipboardContent = Self.clipboardHasContent() }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active { hasClipboardContent = Self.clipboardHasContent() }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
                            hasClipboardContent = Self.clipboardHasContent()
                        }
                }
            }
        }
    }

    private static func clipboardHasContent() -> Bool {
        let board = AppPasteboard.general
        return board.hasStrings || board.hasURLs || board.hasImages
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
