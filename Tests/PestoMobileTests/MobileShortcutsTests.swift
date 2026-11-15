// SPDX-License-Identifier: MIT
import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PestoCore
@testable import PestoMobile

@Suite("The Shortcuts actions")
@MainActor
struct MobileShortcutsTests {
    private let secret = "ghp_8fK2mQ9xLr4TzW7nB1vC6yH3sJ5dE0aGpU2i"

    @Test("Add to Pesto saves text and a picture through ingest, and refuses nothing to add")
    func whenAdded_thenClipsAreIngested() async throws {
        let library = try await MobileTestLibrary()
        let size = CGSize(width: 20, height: 10)
        let png = UIGraphicsImageRenderer(size: size).pngData { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        try await library.state.addFromShortcut(text: "from a shortcut", file: nil, fileType: nil)
        try await library.state.addFromShortcut(text: nil, file: png, fileType: .png)
        try await library.refreshed()

        #expect(library.store.items.contains { $0.displayPreviewText == "from a shortcut" })
        #expect(library.store.items.contains { $0.type == .image })
        await #expect(throws: MobileAppState.ShortcutFailure.nothingToAdd) {
            try await library.state.addFromShortcut(text: "   ", file: nil, fileType: nil)
        }
    }

    @Test("Search Pesto and the clip query never hand out a secret, whatever is asked")
    func whenSearched_thenASecretIsNeverReturned() async throws {
        let library = try await MobileTestLibrary()
        try await library.add("ghp notes for the trip")
        try await library.service.ingest(#require(ClipCapture.text(secret)))
        try await library.refreshed()
        let hidden = try #require(library.store.items.first { $0.sensitivityRaw != nil })

        for query in ["", "ghp", secret, "8fK2"] {
            let found = try library.state.searchForShortcut(query)
            #expect(!found.contains { $0.id == hidden.id || $0.title.contains("8fK2") }, "query \(query)")
        }
        #expect(try library.state.shortcutClips(ids: [hidden.id]).isEmpty)
        let entities = try library.state.searchForShortcut("ghp").map(ClipEntity.init)
        #expect(entities.map(\.text) == ["ghp notes for the trip"])
        #expect(entities.map(\.kind) == ["Text"])
    }
}
