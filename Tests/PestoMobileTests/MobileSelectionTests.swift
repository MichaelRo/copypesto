// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Multi-select Copy All ordering and protection on iOS")
@MainActor
struct MobileSelectionTests {
    @Test("copyJoined joins textual clips in the given order and skips when locked")
    func whenCopyJoined_thenRespectsOrderAndLock() async throws {
        let library = try await MobileTestLibrary()
        let first = try await library.add("Alpha first")
        let second = try await library.add("Beta second")

        let ok = library.state.copyJoined([first, second])
        #expect(ok)
        #expect(library.state.notice?.text == "Copied")

        let lockedLibrary = try await MobileTestLibrary(
            lock: MobileHistoryLock(
                authenticator: StubUserAuthenticator(available: true, grants: true),
                grace: AuthenticationGrace(),
                isEnabled: { true }
            )
        )
        let lockedA = try await lockedLibrary.add("One")
        let lockedB = try await lockedLibrary.add("Two")
        lockedLibrary.state.lockHistory()
        #expect(!lockedLibrary.state.copyJoined([lockedA, lockedB]))
    }

    @Test("copyJoined ignores non-textual clips and needs at least two textual clips")
    func whenFewerThanTwoTextualClips_thenCopyJoinedReturnsFalse() async throws {
        let library = try await MobileTestLibrary()
        let text = try await library.add("Only one text")
        let link = try await library.add("https://copypesto.net")

        #expect(!library.state.copyJoined([text, link]))
    }

    @Test("copyJoined marks clipboard protected when any selected clip is sensitive and reports cap")
    func whenAnySensitiveOrOverCap_thenProtectedAndNoticed() throws {
        let now = Date.now
        let normal = ClipboardItem(
            timestamp: now, type: .text, previewText: "Plain", contentHash: "h1", byteSize: 5,
            deviceID: "d", sequenceNumber: 1
        )
        let secret = ClipboardItem(
            timestamp: now, type: .code, previewText: "token", sensitivity: .apiKey,
            contentHash: "h2", byteSize: 5, deviceID: "d", sequenceNumber: 2
        )
        let over = ClipboardItem(
            timestamp: now, type: .text, previewText: "Too big", contentHash: "h3",
            byteSize: ClipSizePolicy.maxTextBytes, deviceID: "d", sequenceNumber: 3
        )
        let joined = try #require(ClipJoin.join([normal, secret, over]))
        #expect(joined.text == "Plain\n\ntoken")
        #expect(joined.isProtected)
        #expect(joined.leftOut == 1)
    }

    @Test("CardGridLayout.cardIndex maps coordinates to card indices in O(1) and rejects gutters and empty slots")
    func whenPointInsideGrid_thenCardIndexResolvesOrReturnsNil() {
        let cardWidth: CGFloat = 170
        let cardHeight = CardGridLayout.cardHeight(forWidth: cardWidth)
        let spacing = CardGridLayout.spacing

        #expect(CardGridLayout.cardIndex(
            at: CGPoint(x: 20, y: 20), itemCount: 5, columns: 2, cardWidth: cardWidth, cardHeight: cardHeight
        ) == 0)
        #expect(CardGridLayout.cardIndex(
            at: CGPoint(x: cardWidth + spacing + 10, y: 20),
            itemCount: 5, columns: 2, cardWidth: cardWidth, cardHeight: cardHeight
        ) == 1)
        // Strict mode rejects the inter-card gutter; allowsGutter treats it as the preceding column.
        #expect(CardGridLayout.cardIndex(
            at: CGPoint(x: cardWidth + spacing / 2, y: 20),
            itemCount: 5, columns: 2, cardWidth: cardWidth, cardHeight: cardHeight, allowsGutter: false
        ) == nil)
        #expect(CardGridLayout.cardIndex(
            at: CGPoint(x: cardWidth + spacing / 2, y: 20),
            itemCount: 5, columns: 2, cardWidth: cardWidth, cardHeight: cardHeight, allowsGutter: true
        ) == 0)
        // Empty slot in partial last row (5 items in 2 columns -> row 2 col 1 is out of bounds).
        #expect(CardGridLayout.cardIndex(
            at: CGPoint(x: cardWidth + spacing + 20, y: 2 * (cardHeight + spacing) + 10),
            itemCount: 5, columns: 2, cardWidth: cardWidth, cardHeight: cardHeight
        ) == nil)
        #expect(CardGridLayout.cardIndex(
            at: CGPoint(x: 10, y: -5),
            itemCount: 5, columns: 2, cardWidth: cardWidth, cardHeight: cardHeight
        ) == nil)
    }

    @Test("index-based drag selection and O(K log K) ordering stay under 50 ms over 2,000 clips")
    func whenSelectingAndOrderingOver2000Clips_thenStaysFast() {
        let ids = (0..<2000).map { _ in UUID() }
        let result = LibraryListing.Result(ids: ids, animates: false)
        let model = LibraryModel()
        model.beginSelection(with: ids[0])

        let clock = ContinuousClock()
        var totalSeconds = 0.0
        let duration = clock.measure {
            for offset in stride(from: 1, to: 100, by: 2) {
                model.applyDragSelection(
                    fromIndex: 0,
                    toIndex: offset,
                    in: result.ids,
                    baseSelection: [ids[0]],
                    selecting: true
                )
            }
            let ordered = model.selectedClipIDs.sorted {
                (result.indexByID[$0] ?? .max) < (result.indexByID[$1] ?? .max)
            }
            #expect(ordered.count == 100)
            #expect(ordered.first == ids[0])
            #expect(ordered.last == ids[99])
        }
        totalSeconds = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        #expect(totalSeconds < 50, "2,000-clip selection batch took \(totalSeconds) ms")
    }

    @Test("edgeAutoScrollVelocity returns 0 in the middle and ramps quadratically near top and bottom edges")
    func whenTouchApproachesViewportEdges_thenVelocityRampsSmoothly() {
        let minY: CGFloat = 100
        let maxY: CGFloat = 700
        let zone = CardGridLayout.autoScrollEdgeZone
        let maxSpeed = CardGridLayout.autoScrollMaxSpeed

        #expect(CardGridLayout.edgeAutoScrollVelocity(touchY: 400, visibleMinY: minY, visibleMaxY: maxY) == 0)
        #expect(CardGridLayout.edgeAutoScrollVelocity(
            touchY: maxY - zone, visibleMinY: minY, visibleMaxY: maxY
        ) == 0)
        #expect(CardGridLayout.edgeAutoScrollVelocity(
            touchY: minY + zone, visibleMinY: minY, visibleMaxY: maxY
        ) == 0)

        let midBottom = CardGridLayout.edgeAutoScrollVelocity(
            touchY: maxY - zone / 2, visibleMinY: minY, visibleMaxY: maxY
        )
        #expect(abs(midBottom - maxSpeed * 0.25) < 0.01)
        #expect(CardGridLayout.edgeAutoScrollVelocity(
            touchY: maxY + 30, visibleMinY: minY, visibleMaxY: maxY
        ) == maxSpeed)

        let midTop = CardGridLayout.edgeAutoScrollVelocity(
            touchY: minY + zone / 2, visibleMinY: minY, visibleMaxY: maxY
        )
        #expect(abs(midTop + maxSpeed * 0.25) < 0.01)
        #expect(CardGridLayout.edgeAutoScrollVelocity(
            touchY: minY - 30, visibleMinY: minY, visibleMaxY: maxY
        ) == -maxSpeed)

        #expect(CardGridLayout.edgeAutoScrollVelocity(touchY: .nan, visibleMinY: minY, visibleMaxY: maxY) == 0)
        #expect(CardGridLayout.edgeAutoScrollVelocity(touchY: 200, visibleMinY: 300, visibleMaxY: 300) == 0)
    }
}
