// SPDX-License-Identifier: MIT
import AppKit
import Testing
@testable import PestoCore

private let remoteMarker = NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")
private let concealedMarker = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

@Suite("Copies from another device: the setting")
struct RemoteCopyPolicyTests {
    @Test("a copy from another device is kept unless the rules say otherwise")
    func whenRulesKeepRemoteCopies_thenNotBlocked() {
        let rules = ExclusionRules(keepsRemoteCopies: true)

        #expect(rules.blockReason(typeIdentifiers: [], sources: ["com.apple.finder"], isRemote: true) == nil)
    }

    @Test("a copy from another device is dropped when the setting is off, whichever app is in front")
    func whenRulesDropRemoteCopies_thenBlocked() {
        let rules = ExclusionRules(keepsRemoteCopies: false)

        #expect(rules.blockReason(typeIdentifiers: [], sources: ["com.apple.finder"], isRemote: true) == .remoteCopy)
        #expect(rules.blockReason(typeIdentifiers: [], sources: ["com.apple.finder"], isRemote: false) == nil)
    }

    @Test("the setting is off by default")
    func whenSettingUntouched_thenRemoteCopiesAreNotKept() {
        #expect(Setting.keepsRemoteCopies.defaultValue == false)
        #expect(Setting.allNames.contains(Setting.keepsRemoteCopies.name))
    }

    @Test("the frontmost Mac app did not make a copy from another device, so its exclusion does not drop it")
    func whenRemoteCopyAndPasswordManagerInFront_thenKept() {
        let rules = ExclusionRules(keepsRemoteCopies: true)

        #expect(
            rules.blockReason(typeIdentifiers: [], sources: ["com.1password.1password"], isRemote: true) == nil
        )
        #expect(
            rules.blockReason(typeIdentifiers: [], sources: ["com.1password.1password"], isRemote: false)
                == .excludedApp
        )
    }

    @Test("a concealed marker still drops a copy from another device")
    func whenRemoteCopyIsConcealed_thenBlocked() {
        let rules = ExclusionRules(keepsRemoteCopies: true)

        #expect(
            rules.blockReason(typeIdentifiers: [concealedMarker.rawValue], sources: [], isRemote: true)
                == .concealedMarker
        )
    }
}

private struct RemoteFilesResult {
    let captures: CaptureCollector
    let board: FakePasteboard
    let blocks: BlockCollector
}

@Suite("Copies from another device: the watcher")
struct RemoteCopyWatcherTests {
    private func copy(
        rules: ExclusionRules, frontmost: String = "com.apple.Safari", extra: [NSPasteboard.PasteboardType] = []
    ) async
    -> (captures: CaptureCollector, blocks: BlockCollector) {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(pasteboard: board, frontmostProvider: FakeFrontmost(bundleID: frontmost))
        await watcher.updateExclusionRules(rules)
        let captures = CaptureCollector()
        let blocks = BlockCollector()
        await watcher.onCapture { captures.append($0) }
        await watcher.onBlocked { blocks.append($0) }
        board.write(types: [.string, remoteMarker] + extra, data: [.string: Data("hi".utf8)], strings: [.string: "hi"])
        await watcher.tick()
        return (captures, blocks)
    }

    @Test("with the setting on, a copy from another device is captured and marked remote")
    func whenKept_thenCapturedAsRemote() async {
        let result = await copy(rules: ExclusionRules(keepsRemoteCopies: true))

        #expect(result.captures.all.map(\.isRemote) == [true])
        #expect(result.blocks.all.isEmpty)
    }

    @Test("with the setting off, a copy from another device is dropped and counted")
    func whenNotKept_thenBlockedAsRemote() async {
        let result = await copy(rules: ExclusionRules(keepsRemoteCopies: false))

        #expect(result.captures.isEmpty)
        #expect(result.blocks.all == [.remoteCopy])
    }

    @Test("with the setting off, a dropped copy from another device is never read from the pasteboard")
    func whenNotKept_thenItsDataIsNotRead() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari")
        )
        await watcher.updateExclusionRules(ExclusionRules(keepsRemoteCopies: false))
        await watcher.onCapture { _ in }
        board.write(types: [.string, remoteMarker], data: [.string: Data("hi".utf8)], strings: [.string: "hi"])

        await watcher.tick()

        #expect(board.contentReads == 0)
    }

    @Test("a dropped copy leaves the board holding something the history does not, until the next capture")
    func whenCopyDropped_thenBoardHoldsUnrecordedCopyUntilNextCapture() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari")
        )
        await watcher.updateExclusionRules(ExclusionRules(keepsRemoteCopies: false))
        await watcher.onCapture { _ in }
        #expect(await watcher.boardHoldsUnrecordedCopy == false)

        board.write(types: [.string, remoteMarker], data: [.string: Data("a".utf8)], strings: [.string: "a"])
        await watcher.tick()
        #expect(await watcher.boardHoldsUnrecordedCopy)

        board.write(types: [.string], data: [.string: Data("b".utf8)], strings: [.string: "b"])
        await watcher.tick()
        #expect(await watcher.boardHoldsUnrecordedCopy == false)
    }

    @Test("with the setting on, a copy from another device is read")
    func whenKept_thenItsDataIsRead() async {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari")
        )
        await watcher.updateExclusionRules(ExclusionRules(keepsRemoteCopies: true))
        await watcher.onCapture { _ in }
        board.write(types: [.string, remoteMarker], data: [.string: Data("hi".utf8)], strings: [.string: "hi"])

        await watcher.tick()

        #expect(board.contentReads > 0)
    }

    @Test("a copy from another device that lands while a password manager is in front is still kept")
    func whenRemoteCopyArrivesBehindAPasswordManager_thenKept() async {
        let result = await copy(rules: ExclusionRules(keepsRemoteCopies: true), frontmost: "com.1password.1password")

        #expect(result.captures.all.map(\.isRemote) == [true])
        #expect(result.blocks.all.isEmpty)
    }

    @Test("a concealed copy from another device is dropped")
    func whenRemoteAndConcealed_thenBlockedAsConcealed() async {
        let result = await copy(rules: ExclusionRules(keepsRemoteCopies: true), extra: [concealedMarker])

        #expect(result.captures.isEmpty)
        #expect(result.blocks.all == [.concealedMarker])
    }
}

@Suite("Copies from another device: the counter")
struct RemoteCopyStatsTests {
    @Test("a dropped copy from another device is counted on its own and in the total")
    func whenRemoteBlockRecorded_thenCounted() {
        let store = PrivacyStatsStore(defaults: ThrowawayDefaults.make())

        store.record(.remoteCopy)
        store.record(.excludedApp)

        #expect(store.stats.remoteBlocks == 1)
        #expect(store.stats.total == 2)
    }

    @Test("counters saved before the remote count existed still load")
    func whenOldCountersLoaded_thenRemoteIsZero() {
        let defaults = ThrowawayDefaults.make()
        defaults.set(Data(#"{"excludedAppBlocks":3,"concealedBlocks":2}"#.utf8), forKey: PrivacyStatsStore.defaultsKey)

        let stats = PrivacyStatsStore(defaults: defaults).stats

        #expect(stats.excludedAppBlocks == 3)
        #expect(stats.remoteBlocks == 0)
    }

    private func remoteFiles(
        _ urls: [URL],
        keeping: Bool = true
    ) async
    -> RemoteFilesResult {
        let board = FakePasteboard()
        let watcher = PasteboardWatcher(
            pasteboard: board,
            frontmostProvider: FakeFrontmost(bundleID: "com.apple.Safari")
        )
        await watcher.updateExclusionRules(ExclusionRules(keepsRemoteCopies: keeping))
        let captures = CaptureCollector()
        let blocks = BlockCollector()
        await watcher.onCapture { captures.append($0) }
        await watcher.onBlocked { blocks.append($0) }
        board.writeFiles(urls, alsoTypes: [remoteMarker])
        await watcher.tick()
        return RemoteFilesResult(captures: captures, board: board, blocks: blocks)
    }

    private func temporaryFile(_ name: String, bytes: Int = 128) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pesto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(repeating: 9, count: bytes).write(to: url)
        return url
    }

    @Test("a photo copied on another device is kept as a picture, not as a path to a file that is about to go")
    func whenRemotePhoto_thenCapturedAsPictureBytes() async throws {
        let photo = try temporaryFile("IMG_6947.jpeg", bytes: 300)

        let result = await remoteFiles([photo])

        let capture = try #require(result.captures.all.first)
        #expect(capture.typeIdentifier == "public.jpeg")
        #expect(capture.payload.count == 300)
        #expect(capture.isRemote)
    }

    @Test("a file that is not a picture, or several files, from another device are not kept, and are counted")
    func whenRemoteFileIsNotAPicture_thenNothingIsCapturedAndItIsCounted() async throws {
        let pdf = try await remoteFiles([temporaryFile("flight.pdf")])
        #expect(pdf.captures.isEmpty)
        #expect(pdf.blocks.all == [.remoteCopy])
        let two = try await remoteFiles([temporaryFile("a.jpeg"), temporaryFile("b.jpeg")])
        #expect(two.captures.isEmpty)
        #expect(two.blocks.all == [.remoteCopy])
    }

    @Test("a photo that macOS does not let Pesto read is not dropped silently: it is counted as left out")
    func whenRemotePhotoCannotBeRead_thenCountedAsLeftOut() async {
        let unreadable = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-\(UUID().uuidString)/IMG_1.jpeg")

        let result = await remoteFiles([unreadable])

        #expect(result.captures.isEmpty)
        #expect(result.blocks.all == [.remoteCopy])
    }

    @Test("with the setting off a remote photo is dropped before its file is read")
    func whenRemotePhotoAndSettingOff_thenNotRead() async throws {
        let photo = try temporaryFile("IMG_1.jpeg")

        let result = await remoteFiles([photo], keeping: false)

        #expect(result.captures.isEmpty)
        #expect(result.board.contentReads == 0)
    }
}
