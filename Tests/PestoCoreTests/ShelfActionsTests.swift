// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Shelf actions")
struct ShelfActionsTests {
    private func clip(
        _ text: String, type: ClipboardType = .text, secret: Bool = false, withBlob: Bool = true
    )
    throws -> ClipboardItem {
        let item = ClipboardItem(
            type: type, previewText: withBlob ? "" : text, contentHash: UUID().uuidString, byteSize: text.utf8.count,
            deviceID: "test", sequenceNumber: 1
        )
        if secret { item.sensitivityRaw = SensitivityCategory.apiKey.rawValue }
        if withBlob {
            let id = item.id
            let sealed = try BlobEncryption().encrypt(
                Data(text.utf8), associatedData: BlobEncryption.associatedData(itemID: id, field: .blob)
            )
            let blob = ClipboardBlob(
                encryptedData: sealed.ciphertext, nonceData: sealed.nonce, mimeType: "public.utf8-plain-text"
            )
            blob.aadBound = true
            item.blob = blob
        }
        return item
    }

    // MARK: Taps

    @Test("in the pinned window's copy-only mode a single click copies, and the second click of a double does nothing")
    func whenCopyOnly_thenCopyOnce() {
        #expect(ShelfTap.route(copyOnly: true, hasSelection: true, extendsSelection: false, click: .single) == .copy)
        #expect(ShelfTap.route(copyOnly: true, hasSelection: false, extendsSelection: true, click: .single) == .copy)
        #expect(ShelfTap.route(copyOnly: true, hasSelection: false, extendsSelection: false, click: .double) == .ignore)
    }

    @Test(
        "in the pinned window with auto-paste on a single click pastes, and the second click of a double does nothing"
    )
    func whenPinnedAutoPaste_thenPasteOnce() {
        #expect(ShelfTap.route(
            copyOnly: false, pastesOnClick: true, hasSelection: false, extendsSelection: false, click: .single
        ) == .paste)
        #expect(ShelfTap.route(
            copyOnly: false, pastesOnClick: true, hasSelection: false, extendsSelection: false, click: .double
        ) == .ignore)
    }

    @Test("a single click only focuses the card; a double click pastes it")
    func whenNoSelection_thenSingleFocusesAndDoublePastes() {
        #expect(ShelfTap.route(copyOnly: false, hasSelection: false, extendsSelection: false, click: .single) == .focus)
        #expect(ShelfTap.route(copyOnly: false, hasSelection: false, extendsSelection: false, click: .double) == .paste)
    }

    @Test("with a selection a click toggles the card, and the second click of a double does not toggle it back")
    func whenSelecting_thenToggleOnce() {
        #expect(ShelfTap
            .route(copyOnly: false, hasSelection: true, extendsSelection: false, click: .single) == .toggleSelection)
        #expect(ShelfTap.route(copyOnly: false, hasSelection: true, extendsSelection: false, click: .double) == .ignore)
    }

    @Test("a click with ⌘ or ⇧ held starts or extends a selection")
    func whenModifierHeld_thenToggle() {
        #expect(ShelfTap
            .route(copyOnly: false, hasSelection: false, extendsSelection: true, click: .single) == .toggleSelection)
        #expect(ShelfTap.route(copyOnly: false, hasSelection: false, extendsSelection: true, click: .double) == .ignore)
    }

    @Test("the accessibility action pastes in one step, copies in copy-only mode and toggles inside a selection")
    func whenActivated_thenOneStep() {
        #expect(ShelfTap
            .route(copyOnly: false, hasSelection: false, extendsSelection: false, click: .activate) == .paste)
        #expect(ShelfTap.route(copyOnly: true, hasSelection: false, extendsSelection: false, click: .activate) == .copy)
        #expect(ShelfTap
            .route(copyOnly: false, hasSelection: true, extendsSelection: false, click: .activate) == .toggleSelection)
    }

    // MARK: Delete targets

    @Test("the Delete key removes the whole selection when there is one, and the focused clip otherwise")
    func deleteKey_targetsTheSelectionOrTheFocusedClip() {
        let a = UUID(), b = UUID(), c = UUID()

        #expect(ShelfDeletion.targets(selection: [a, b], focused: c) == [a, b])
        #expect(ShelfDeletion.targets(selection: [], focused: c) == [c])
        #expect(ShelfDeletion.targets(selection: [], focused: nil).isEmpty)
    }

    @Test("a card's own Delete removes the selection only when that card is part of it")
    func cardDelete_targetsTheSelectionOnlyWhenTheCardIsInIt() {
        let a = UUID(), b = UUID(), c = UUID()

        #expect(ShelfDeletion.targets(selection: [a, b], requestedFor: a) == [a, b])
        #expect(ShelfDeletion.targets(selection: [a, b], requestedFor: c) == [c])
        #expect(ShelfDeletion.targets(selection: [a], requestedFor: a) == [a])
        #expect(ShelfDeletion.targets(selection: [], requestedFor: c) == [c])
    }

    // MARK: Paste routing

    @Test("a paste is ignored while the history is locked or another is in flight")
    func whenLockedOrBusy_thenIgnored() {
        #expect(ShelfPaste.route(isLocked: true, isPasting: false, pinnedWindow: false) == .ignore)
        #expect(ShelfPaste.route(isLocked: false, isPasting: true, pinnedWindow: true) == .ignore)
    }

    @Test("the pinned window pastes in place and the shelf closes to paste")
    func whenFree_thenRouteByWindow() {
        #expect(ShelfPaste.route(isLocked: false, isPasting: false, pinnedWindow: true) == .inPlace)
        #expect(ShelfPaste.route(isLocked: false, isPasting: false, pinnedWindow: false) == .closeShelfThenPaste)
    }

    // MARK: Text, Paste All and Paste One by One

    @Test("a clip's text is its decrypted blob, or its preview when it has none")
    func whenReadingText_thenBlobThenPreview() throws {
        #expect(try ClipText.full(of: clip("the whole text")) == "the whole text")
        #expect(try ClipText.full(of: clip("only a preview", withBlob: false)) == "only a preview")
    }

    @Test("Paste All joins the texts with a blank line, and is protected when any clip is")
    func whenPastingAll_thenJoinedAndProtected() throws {
        let joined = try #require(try ClipJoin.join([clip("one"), clip("two", secret: true), clip("three")]))

        #expect(joined.text == "one\n\ntwo\n\nthree")
        #expect(joined.isProtected)
        #expect(try ClipJoin.join([clip("a"), clip("b")])?.isProtected == false)
    }

    @Test("Paste All stops at the size limit and does not read the clips it leaves out (P-07)")
    func whenTheJoinIsTooBig_thenLaterClipsAreLeftOutUnread() throws {
        let big = try clip("first")
        big.byteSize = ClipSizePolicy.maxTextBytes - 100
        let second = try clip("second")
        second.byteSize = 80
        let third = try clip("third", withBlob: false)
        third.byteSize = 5_000_000
        third.blob = ClipboardBlob(encryptedData: Data([1, 2, 3]), nonceData: Data(count: 12), mimeType: "text/plain")

        let joined = try #require(ClipJoin.join([big, second, third]))

        #expect(joined.text == "first\n\nsecond")
        #expect(joined.leftOut == 1)
    }

    @Test("a stack takes clips only up to its byte limit, and always the first one")
    func whenTheStackIsTooBig_thenItIsCut() {
        let sizes = [PasteStack.maxTotalBytes - 10, 5, 20, 5]
        let result = PasteStack.limited(sizes, byteSize: { $0 })
        #expect(result.kept == [sizes[0], 5])
        #expect(result.leftOut == 2)
        #expect(PasteStack.limited([PasteStack.maxTotalBytes * 2], byteSize: { $0 }).kept.count == 1)
    }

    @Test("fewer than two clips join into nothing")
    func whenOneClip_thenNothingToJoin() throws {
        #expect(try ClipJoin.join([clip("alone")]) == nil)
        #expect(ClipJoin.join([]) == nil)
    }

    @Test("a text clip becomes a stack item holding its plain bytes, protected when it is a secret")
    func whenStackingText_thenBytesAndKind() throws {
        let item = try PasteStack.Item(clip: clip("stack me", secret: true))

        #expect(item.pasteboardData == Data("stack me".utf8))
        #expect(item.pasteboardType == "public.utf8-plain-text")
        #expect(item.isProtected)
        if case let .text(text) = item.payloadKind { #expect(text == "stack me") } else { Issue.record("not text") }
    }

    @Test("a picture becomes a non-text stack item, and a clip with no blob falls back to its preview")
    func whenStackingOtherKinds_thenKindFollowsTheType() throws {
        let picture = try PasteStack.Item(clip: clip("not really pixels", type: .image))
        #expect({ if case .nonText = picture.payloadKind { true } else { false } }())

        let bare = try PasteStack.Item(clip: clip("snippet", withBlob: false))
        #expect(bare.pasteboardData == nil)
        if case let .text(text) = bare.payloadKind { #expect(text == "snippet") } else { Issue.record("not text") }
    }

    @Test("quick paste last takes the second clip when the newest one is what is on the clipboard")
    func whenBoardHoldsTheNewestClip_thenQuickPasteLastTakesTheSecond() {
        #expect(QuickPasteLast.index(historyCount: 3, boardHoldsUnrecordedCopy: false) == 1)
    }

    @Test("quick paste last takes the newest clip when the clipboard holds a copy that was dropped")
    func whenBoardHoldsADroppedCopy_thenQuickPasteLastTakesTheNewest() {
        #expect(QuickPasteLast.index(historyCount: 3, boardHoldsUnrecordedCopy: true) == 0)
    }

    @Test("quick paste last has nothing to paste without a previous clip")
    func whenTooFewClips_thenQuickPasteLastHasNothing() {
        #expect(QuickPasteLast.index(historyCount: 1, boardHoldsUnrecordedCopy: false) == nil)
        #expect(QuickPasteLast.index(historyCount: 0, boardHoldsUnrecordedCopy: true) == nil)
        #expect(QuickPasteLast.index(historyCount: 1, boardHoldsUnrecordedCopy: true) == 0)
    }
}
