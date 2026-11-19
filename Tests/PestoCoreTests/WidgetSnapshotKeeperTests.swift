// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore

@Suite("The Mac keeps its widget snapshot only while a widget is installed, and empty while locked or covered")
@MainActor
final class WidgetSnapshotKeeperTests {
    private let root: URL
    private let container: ModelContainer
    private let context: ModelContext
    private let secrets = MemorySecrets()
    private var installed: Bool? = true
    private var gate = WidgetSnapshotGate.clips
    private var readable = true
    private var reloads = 0
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var keeper: WidgetSnapshotKeeper?
    private let readGate = ReadGate()

    /// Holds the first clip read of a write until the test lets it go, so the test can act while the write is off the
    /// main actor.
    private final class ReadGate: @unchecked Sendable {
        private let lock = NSLock()
        private var armed = false
        let started = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)

        func waitUntilStarted() {
            started.wait()
        }

        func arm() {
            lock.withLock { armed = true }
        }

        func pass() {
            let wait = lock.withLock {
                defer { armed = false }
                return armed
            }
            guard wait else { return }
            started.signal()
            proceed.wait()
        }
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-mac-widget-\(UUID().uuidString)", isDirectory: true)
        container = try ModelContainerSetup.makeInMemory()
        context = ModelContext(container)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private var file: SealedGroupFile {
        SealedGroupFile(root: root, format: .widgetSnapshot)
    }

    private var keys: SharedFileKeyStore {
        SharedFileKeyStore(secrets: secrets, account: AppIdentity.widgetKeyAccount)
    }

    private func makeKeeper() -> WidgetSnapshotKeeper {
        let target = WidgetSnapshotKeeper.Target(
            file: file, keys: keys,
            isInstalled: { [unowned self] in installed },
            reload: { [unowned self] in reloads += 1 }
        )
        let inputs = WidgetSnapshotKeeper.Inputs(
            gate: { [unowned self] in gate }, theme: { .brand }, canRead: { [unowned self] in readable },
            source: { [readGate] _ in
                readGate.pass()
                return "Notes"
            }, now: { [unowned self] in clock }
        )
        let made = WidgetSnapshotKeeper(target: target, container: container, inputs: inputs, rewriteDelay: .zero)
        keeper = made
        return made
    }

    private func add(_ preview: String) throws {
        clock += 60
        let item = ClipboardItem(
            type: .text, previewText: preview, contentHash: UUID().uuidString, byteSize: preview.utf8.count,
            deviceID: "t", sequenceNumber: 1
        )
        item.timestamp = clock
        context.insert(item)
        try context.saveOrRollback()
    }

    private func written() throws -> WidgetSnapshot {
        let key = try #require(try keys.key())
        return try file.read(WidgetSnapshot.self, with: key)
    }

    @Test("with no widget installed there is no file and the Keychain is never asked")
    func whenNoWidgetIsInstalled_thenNothingIsWritten() async throws {
        installed = false
        try add("lunch at noon")
        let keeper = makeKeeper()

        await keeper.start()
        keeper.historyChanged()
        await keeper.stateMayHaveChanged()

        #expect(!file.exists)
        #expect(secrets.readCount == 0)
        keeper.stop()
    }

    @Test("an installed widget gets the newest clips, sealed, and its timeline is reloaded")
    func whenAWidgetIsInstalled_thenTheClipsAreWritten() async throws {
        try add("lunch at noon")
        try add("the second note")
        let keeper = makeKeeper()

        await keeper.start()

        let snapshot = try written()
        #expect(snapshot.clips.map(\.text) == ["the second note", "lunch at noon"])
        #expect(snapshot.clips.first?.source == "Notes")
        #expect(try Data(contentsOf: file.url).range(of: Data("lunch".utf8)) == nil)
        #expect(reloads == 1)
        keeper.stop()
    }

    @Test("the lock switched on writes Locked and the cover Hidden, with no clip; lifted, the clips come back")
    func whenTheLockOrTheCoverMove_thenTheSnapshotFollows() async throws {
        try add("lunch at noon")
        let keeper = makeKeeper()
        gate = .locked
        await keeper.start()
        #expect(try written().isLocked)
        #expect(try written().clips.isEmpty)

        gate = .hidden
        await keeper.stateMayHaveChanged()
        #expect(try written().isHidden)
        #expect(try written().clips.isEmpty)

        let reloadsBefore = reloads
        await keeper.stateMayHaveChanged()
        #expect(reloads == reloadsBefore, "an unchanged state is not written again")

        gate = .clips
        await keeper.stateMayHaveChanged()
        #expect(try written().clips.map(\.text) == ["lunch at noon"])
        keeper.stop()
    }

    @Test("a save to the history is in the snapshot a moment later")
    func whenTheHistoryChanges_thenTheSnapshotIsRewritten() async throws {
        let keeper = makeKeeper()
        await keeper.start()
        #expect(try written().clips.isEmpty)

        try add("a fresh copy")
        var texts: [String] = []
        for _ in 0..<100 {
            texts = try written().clips.map(\.text)
            if !texts.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(texts == ["a fresh copy"])
        keeper.stop()
    }

    @Test("a widget removed takes the file and the key with it; an unreadable history leaves no file")
    func whenTheWidgetGoesOrTheHistoryCannotBeRead_thenTheFileGoes() async throws {
        try add("lunch at noon")
        let keeper = makeKeeper()
        await keeper.start()
        #expect(file.exists)

        installed = false
        await keeper.refreshPresence()
        #expect(!file.exists)
        #expect(try keys.key() == nil)

        installed = true
        await keeper.refreshPresence()
        #expect(file.exists)
        readable = false
        await keeper.write()
        #expect(!file.exists)
        keeper.stop()
    }

    @Test("asking again with nothing changed writes nothing: no Keychain read, no seal, no reload")
    func whenPresenceIsUnchanged_thenNothingIsWritten() async throws {
        try add("lunch at noon")
        let keeper = makeKeeper()
        await keeper.start()
        let reloadsAfterStart = reloads
        let readsAfterStart = secrets.readCount
        let written = try Data(contentsOf: file.url)

        await keeper.refreshPresence()
        await keeper.refreshPresence()

        #expect(reloads == reloadsAfterStart)
        #expect(secrets.readCount == readsAfterStart)
        #expect(try Data(contentsOf: file.url) == written)
        keeper.stop()
    }

    @Test("a widget removed while a write is running leaves no file and no key behind")
    func whenTheWidgetGoesDuringAWrite_thenNothingIsRecreated() async throws {
        try add("lunch at noon")
        let keeper = makeKeeper()
        await keeper.start()

        readGate.arm()
        let running = Task { await keeper.write() }
        let gate = readGate
        await Task.detached { gate.waitUntilStarted() }.value
        installed = false
        await keeper.refreshPresence()
        gate.proceed.signal()
        await running.value

        #expect(!file.exists)
        #expect(try keys.key() == nil)
        keeper.stop()
    }

    @Test("WidgetKit failing to answer is not a removed widget: the snapshot and key stay")
    func whenWidgetKitFails_thenTheSnapshotStays() async throws {
        try add("lunch at noon")
        let keeper = makeKeeper()
        await keeper.start()

        installed = nil
        await keeper.refreshPresence()

        #expect(file.exists)
        #expect(try keys.key() != nil)
        #expect(keeper.isInstalled)
        keeper.stop()
    }
}
