// SPDX-License-Identifier: MIT
import AppIntents
import Foundation
import PestoCore

/// A clip as Shortcuts sees it: its id, a line of its text and its kind. Built only from a `ShortcutClip`, so a
/// secret, a clip still being judged or one the content filter covers is never one.
struct ClipEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Clip"
    static let defaultQuery = ClipEntityQuery()

    let id: UUID
    @Property(title: "Text") var text: String
    @Property(title: "Kind") var kind: String

    init(_ clip: ShortcutClip) {
        id = clip.id
        text = clip.title
        kind = clip.kindLabel
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(text)", subtitle: "\(kind)")
    }
}

struct ClipEntityQuery: EntityStringQuery {
    @Dependency private var state: MobileAppState

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ClipEntity] {
        try state.shortcutClips(ids: identifiers).map(ClipEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ClipEntity] {
        try state.searchForShortcut(string).map(ClipEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [ClipEntity] {
        try state.searchForShortcut("", limit: 10).map(ClipEntity.init)
    }
}
