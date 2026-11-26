// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

extension MobilePasteboardGlobals {
    @Suite("Batch 1: iOS collections, multi-select, card actions, and hit bounds")
    @MainActor
    struct MobileBatch1Tests {
        @Test("adding a note or paste inside a plain collection assigns that collection")
        func whenClipAddedIntoCollection_thenCollectionIDIsAssigned() async throws {
            let library = try await MobileTestLibrary()
            let board = try #require(library.state.addCollection(named: "Recipes", existing: []))

            let added = await library.state.add(ClipCapture.text("basil leaves"), into: board.id)
            #expect(added)
            let item = try await library.settle()
            #expect(item.collectionID == board.id)
        }

        @Test("multi-select mode tracks selected clips and closes cleanly on lock")
        func whenSelectingClips_thenSelectionTracksAndResetsOnClose() {
            let model = LibraryModel()
            let first = UUID()
            let second = UUID()

            model.beginSelection(with: first)
            #expect(model.isSelecting)
            #expect(model.selectedClipIDs == [first])

            model.toggleSelection(second)
            #expect(model.selectedClipIDs == [first, second])

            model.toggleSelection(first)
            #expect(model.selectedClipIDs == [second])

            model.selectAll([first, second])
            #expect(model.selectedClipIDs == [first, second])

            model.closeEverything()
            #expect(!model.isSelecting)
            #expect(model.selectedClipIDs.isEmpty)
        }

        @Test("drag-selection selects and deselects contiguous ranges across visible cards")
        func whenDragSelected_thenRangeUpdates() {
            let model = LibraryModel()
            let ids = (0..<5).map { _ in UUID() }
            model.beginSelection()

            model.applyDragSelection(
                from: ids[1], to: ids[3], in: ids, baseSelection: [], selecting: true
            )
            #expect(model.selectedClipIDs == Set([ids[1], ids[2], ids[3]]))

            model.applyDragSelection(
                from: ids[3], to: ids[2], in: ids, baseSelection: Set([ids[1], ids[2], ids[3]]), selecting: false
            )
            #expect(model.selectedClipIDs == Set([ids[1]]))
        }

        @Test("hidden mobile collections filter the iPhone chip row without removing the collections")
        func whenCollectionIsHidden_thenChipRowOmitsIt() {
            let first = UUID()
            let second = UUID()
            let stored = HiddenCollections.toggle(first, in: "")
            #expect(HiddenCollections.ids(from: stored) == [first])

            let chips = LibraryChip.row(
                collectionIDs: [first, second], isSearching: false, hiddenIDs: HiddenCollections.ids(from: stored)
            )
            #expect(chips == [.all, .pinned, .collection(second), .newCollection])

            let unhidden = HiddenCollections.toggle(first, in: stored)
            #expect(HiddenCollections.ids(from: unhidden).isEmpty)
        }

        @Test("moving a collection left or right updates sortOrder through Undo")
        func whenCollectionMovedLeftOrRight_thenSortOrderUpdates() async throws {
            let library = try await MobileTestLibrary()
            let first = try #require(library.state.addCollection(named: "First", existing: []))
            let second = try #require(library.state.addCollection(named: "Second", existing: [first]))
            let boards = [first, second]

            library.state.moveCollection(second, direction: -1, among: boards)
            #expect(second.sortOrder < first.sortOrder)
            #expect(library.state.undoHistory?.undoLabel == .reorderCollections)

            await library.state.undo()
            try await library.refreshed()
            let context = try ModelContext(#require(library.state.historyContainer))
            let fetched = try context.fetch(FetchDescriptor<Pinboard>(sortBy: [SortDescriptor(\.sortOrder)]))
            #expect(fetched.map(\.name) == ["First", "Second"])
        }

        @Test("toggling sensitivity on iOS marks and unmarks NSFW undoably")
        func whenToggleSensitive_thenISNSFWUpdates() async throws {
            let library = try await MobileTestLibrary()
            let item = try await library.add("https://example.com/pic.png")
            #expect(!item.isNSFW)

            library.state.toggleSensitive(item)
            #expect(item.isNSFW)
            #expect(library.state.undoHistory?.undoLabel != nil)

            library.state.toggleSensitive(item)
            #expect(!item.isNSFW)
        }

        @Test("tall portrait pictures clip their interaction bounds to the card frame")
        func whenPortraitPictureCardUnderTopCard_thenTopCardReceivesBottomTouch() async throws {
            let library = try await MobileTestLibrary()
            let tallPortrait = UIGraphicsImageRenderer(size: CGSize(width: 90, height: 240)).image { ctx in
                UIColor.systemBlue.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 90, height: 240))
            }
            let context = try ModelContext(#require(library.state.historyContainer))
            let item1 = ClipboardItem(
                type: .image, previewText: "", contentHash: "p1", byteSize: 100, deviceID: "d", sequenceNumber: 1
            )
            let item2 = ClipboardItem(
                type: .image, previewText: "", contentHash: "p2", byteSize: 100, deviceID: "d", sequenceNumber: 2
            )
            context.insert(item1)
            context.insert(item2)

            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let shape = RoundedRectangle(cornerRadius: CardGridLayout.cornerRadius, style: .continuous)
            let cardSize = CGSize(width: 170, height: 153)
            let stack = VStack(spacing: 12) {
                PictureCardFace(image: tallPortrait, fit: .fit) {
                    Text("Card 1")
                }
                .frame(width: cardSize.width, height: cardSize.height)
                .clipShape(shape)
                .contentShape(shape)

                PictureCardFace(image: tallPortrait, fit: .fit) {
                    Text("Card 2")
                }
                .frame(width: cardSize.width, height: cardSize.height)
                .clipShape(shape)
                .contentShape(shape)
            }
            .environment(library.state)

            let host = UIHostingController(rootView: stack)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 200, height: 360)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))

            let topPoint = host.view.convert(CGPoint(x: 100, y: 145), to: window)
            let bottomPoint = host.view.convert(CGPoint(x: 100, y: 220), to: window)
            #expect(window.hitTest(topPoint, with: nil) != nil)
            #expect(window.hitTest(bottomPoint, with: nil) != nil)
        }
    }
}
