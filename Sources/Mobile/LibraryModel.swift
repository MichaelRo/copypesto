// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore
import SwiftUI

/// What the one library page is showing and what it has open, kept above the compact and regular layouts so a change
/// of width (Split View, rotation) keeps the scope, the search and the open clip.
@MainActor
@Observable
final class LibraryModel {
    var filter = LibraryFilter()
    var query = ""
    var isSearching = false
    var openClipID: UUID?
    var columns: NavigationSplitViewVisibility = .all
    var showsSettings = false
    var isComposing = false
    var isNamingCollection = false
    var renaming: Pinboard?
    var pendingDelete: UUID?
    var sharing: ClipShare?
    var flashedClipID: UUID?
    var copyCount = 0

    func open(_ id: UUID) {
        openClipID = id
    }

    func didCopy(_ id: UUID) {
        copyCount += 1
        flashedClipID = id
        let count = copyCount
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, copyCount == count else { return }
            flashedClipID = nil
        }
    }

    func endSearch() {
        filter.endSearch()
    }
}
