// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SnapshotTesting
import SwiftData
import SwiftUI
import XCTest
@testable import Pesto

/// Ask in the Find bar, drawn forward for a question with its ⌘Return on it, and Ask Pesto first on No results, as
/// on the iPhone.
@MainActor
final class AskOfferSnapshotTests: XCTestCase {
    private func snapshot(
        _ view: some View, size: CGSize, file: StaticString = #filePath, testName: String = #function,
        line: UInt = #line
    ) {
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.92))
            .defaultAppStorage(AppDefaults.store)
            .preferredColorScheme(.light)
            .inBrandAccent()
        let controller = NSHostingController(rootView: root)
        controller.view.appearance = NSAppearance(named: .aqua)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(of: controller, as: .image(size: size), file: file, testName: testName, line: line)
        }
    }

    func test_whenSearchReadsLikeAQuestion_thenAskIsDrawnForwardWithItsShortcut() throws {
        let container = try ModelContainerSetup.makeInMemory()
        let appState = AppState()
        appState.historyContainer = container
        appState.historyStore = HistoryStore(container: container)
        appState.isSearchActive = true
        appState.searchText = "links from slack last week"
        snapshot(
            CommandBarView().padding(.horizontal, 16).environment(appState).modelContainer(container),
            size: CGSize(width: 1512, height: 60)
        )
    }

    func test_whenNoResultsForAQuestion_thenAskPestoComesFirst() {
        snapshot(
            ShelfEmptyStateView(
                state: .noResults, query: "links from slack last week",
                advice: NoResultsAdvice.make(query: "links from slack last week"), asksFirst: true, onAsk: {}
            ),
            size: CGSize(width: 520, height: 280)
        )
    }
}
