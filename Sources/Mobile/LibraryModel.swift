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
    var editingCollection: Pinboard?
    var pendingDelete: UUID?
    var sharing: ClipShare?
    var flashedClipID: UUID?
    var copyCount = 0
    /// Bumped when the grid should take the history's order again (`GridOrder`).
    private(set) var orderVersion = 0
    @ObservationIgnored let order = GridOrder()

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

    /// A clip from the widget: the library goes back to All, out of any search, and takes the history's order (a copy
    /// moved the clip to the front). A copied clip's card flashes; a clip opened from the widget opens in its detail.
    func show(_ id: UUID, opensDetail: Bool) {
        filter = LibraryFilter()
        query = ""
        isSearching = false
        openClipID = nil
        resort()
        if opensDetail {
            open(id)
        } else {
            didCopy(id)
        }
    }

    func resort() {
        order.resort()
        orderVersion += 1
    }

    func endSearch() {
        filter.endSearch()
    }
}
