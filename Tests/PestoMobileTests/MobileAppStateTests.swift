// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import SwiftData
import Testing
import UIKit
@testable import PestoCore
@testable import PestoMobile

@Suite("The iOS app opens its history")
@MainActor
struct MobileAppStateTests {
    private struct StoreWillNotOpen: Error {}

    private func textCapture(_ text: String) -> PasteboardCapture {
        PasteboardCapture(
            typeIdentifier: "public.utf8-plain-text",
            payload: Data(text.utf8),
            payloadString: text,
            contentHash: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func bytes(under directory: URL) throws -> [Data] {
        let enumerator = try #require(FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        ))
        var files: [Data] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            try files.append(Data(contentsOf: url))
        }
        return files
    }

    private func diskOpeners(in directory: URL) -> StorageBoot.Openers {
        .init(
            clips: { try ModelContainerSetup.openClips(storeURL: directory.appendingPathComponent("clips.store")) },
            inMemory: { try ModelContainerSetup.makeInMemory() }
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-mobile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("a first launch opens the store on disk, with a history and a storage service on it")
    func whenBooted_thenTheStoreIsOnDisk() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = MobileAppState()

        state.boot(openers: diskOpeners(in: directory))
        await state.launchWork?.value

        #expect(state.storeIsOnDisk)
        #expect(state.historyStore != nil)
        #expect(state.storageService != nil)
    }

    @Test("a picture left waiting for its text recognition when Pesto was stopped is judged at the next launch")
    func whenAPictureWasLeftPending_thenTheNextLaunchJudgesIt() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("clips.store")
        let png = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        }
        let id: UUID
        do {
            let container = try ModelContainerSetup.openClips(storeURL: storeURL)
            let service = StorageService(modelContainer: container, environment: .testing())
            try await service.ingest(#require(ClipCapture.picture(png, typeIdentifier: "public.png")))
            await service.waitForBackgroundWork()
            let context = ModelContext(container)
            let picture = try #require(context.fetch(FetchDescriptor<ClipboardItem>()).first)
            picture.analysisPending = true
            try context.saveOrRollback()
            id = picture.id
        }

        let library = try await MobileTestLibrary(storeURL: storeURL)
        await library.service.waitForBackgroundWork()

        let context = try ModelContext(#require(library.state.historyContainer))
        let picture = try #require(context.fetch(FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id }))
            .first)
        #expect(!picture.analysisPending)
    }

    @Test("when the disk store will not open, the history is kept in memory and the app knows it")
    func whenTheDiskStoreFails_thenTheHistoryIsInMemory() {
        let state = MobileAppState()

        state.boot(openers: .init(
            clips: { throw StoreWillNotOpen() },
            inMemory: { try ModelContainerSetup.makeInMemory() }
        ))

        #expect(!state.storeIsOnDisk)
        #expect(state.historyStore != nil)
    }

    @Test("when no store opens at all, the app has booted without a history instead of crashing")
    func whenNoStoreOpens_thenThereIsNoHistory() {
        let state = MobileAppState()

        state.boot(openers: .init(clips: { throw StoreWillNotOpen() }, inMemory: { throw StoreWillNotOpen() }))

        #expect(state.hasBooted)
        #expect(state.historyStore == nil)
        #expect(state.storageService == nil)
    }

    @Test("a clip added on iOS reaches the history list, and its text is nowhere in the files on disk")
    func whenAClipIsAdded_thenItIsListedAndSealed() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = MobileAppState()
        state.boot(openers: diskOpeners(in: directory))
        await state.launchWork?.value
        let service = try #require(state.storageService)
        let store = try #require(state.historyStore)
        let text = "packing list \(UUID().uuidString)"

        try await service.ingest(textCapture(text))
        await service.waitForBackgroundWork()
        store.setVisible(true)
        store.refresh()
        try await store.waitForRefresh()

        #expect(store.items.map(\.gridPreview) == [text])
        let needle = Data(text.utf8)
        #expect(try bytes(under: directory).allSatisfy { $0.range(of: needle) == nil })
    }

    @Test("iOS never writes the last-item file, the preview a Mac keeps in the clear for its command-line tool")
    func whenLaunchedNormally_thenNoLastItemFileIsWritten() {
        #expect(StorageEnvironment.lastItemStore(for: .normal) is NoLastItemFile)
        #expect(StorageEnvironment.lastItemStore(for: .uiTest) is NoLastItemFile)
    }
}
