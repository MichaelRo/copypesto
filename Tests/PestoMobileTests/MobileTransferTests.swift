// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("iOS collection .pesto and history JSON export/import")
@MainActor
struct MobileTransferTests {
    @Test("history JSON exports textual clips and imports new ones without duplicates")
    func whenHistoryExportedAndImportedAsJSON_thenRoundTrips() async throws {
        let source = try await MobileTestLibrary()
        try await source.add("First clip")
        try await source.add("https://copypesto.net")

        let exportedURL = try #require(await source.state.exportHistoryJSON())
        defer { ShareFile.remove(exportedURL) }
        #expect(exportedURL.pathExtension == "json")

        let destination = try await MobileTestLibrary()
        await destination.state.importHistoryJSON(from: exportedURL)
        try await destination.refreshed()

        #expect(destination.store.items.count == 2)
        #expect(destination.state.notice?.isProblem == false)

        await destination.state.importHistoryJSON(from: exportedURL)
        #expect(destination.state.notice?.text == String(localized: "Nothing new."))
    }

    @Test("opening a .pesto collection URL prepares a confirmation preview, then imports with Undo")
    func whenCollectionFileOpened_thenPreviewsAndImportsWithUndo() async throws {
        let source = try await MobileTestLibrary()
        let board = try #require(source.state.addCollection(named: "Recipes", existing: []))
        let clip = try await source.add("Basil, garlic, pine nuts")
        source.state.moveToCollection(clip, collectionID: board.id)

        let exportedURL = try #require(await source.state.exportCollection(board))
        defer { ShareFile.remove(exportedURL) }
        #expect(exportedURL.pathExtension == CollectionFileType.fileExtension)

        let destination = try await MobileTestLibrary()
        let outcome = destination.state.open(exportedURL)
        #expect(outcome == .shown)
        await destination.state.collectionImportPreparationTask?.value

        let pending = try #require(destination.state.pendingCollectionImport)
        #expect(pending.preview.name == "Recipes")
        #expect(pending.preview.importableCount == 1)

        await destination.state.confirmPendingCollectionImport()
        try await destination.refreshed()

        #expect(destination.state.pendingCollectionImport == nil)
        #expect(destination.store.items.map(\.displayPreviewText).contains("Basil, garlic, pine nuts"))
        #expect(destination.state.undoOffer != nil)
        #expect(destination.state.notice?.isProblem == false)
    }

    @Test("canceling a pending collection import clears the state and deletes the staged temp file")
    func whenPendingCollectionImportCanceled_thenCleansUpTempFile() async throws {
        let source = try await MobileTestLibrary()
        let board = try #require(source.state.addCollection(named: "Temp", existing: []))
        let clip = try await source.add("Temporary note")
        source.state.moveToCollection(clip, collectionID: board.id)

        let exportedURL = try #require(await source.state.exportCollection(board))
        defer { ShareFile.remove(exportedURL) }

        let destination = try await MobileTestLibrary()
        await destination.state.prepareCollectionImport(from: exportedURL)

        let stagedURL = try #require(destination.state.pendingCollectionImport?.cleanupURL)
        #expect(FileManager.default.fileExists(atPath: stagedURL.path))

        destination.state.cancelPendingCollectionImport()
        #expect(destination.state.pendingCollectionImport == nil)
        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
    }

    @Test("opening a .pesto file while locked holds the URL without importing")
    func whenCollectionFileOpenedWhileLocked_thenHoldsLink() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("locked-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let fileURL = folder.appendingPathComponent("Work.pesto")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("{}".utf8))

        let lock = MobileHistoryLock(
            authenticator: StubUserAuthenticator(available: true, grants: true),
            grace: AuthenticationGrace(),
            isEnabled: { true }
        )
        lock.lock()
        let library = try await MobileTestLibrary(lock: lock)

        let outcome = library.state.open(fileURL)
        #expect(outcome == .shown)
        #expect(library.state.heldLink == fileURL)
        #expect(library.state.pendingCollectionImport == nil)
    }

    @Test("opening an invalid .pesto file reports an error notice")
    func whenInvalidCollectionFileOpened_thenShowsProblemNotice() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let badURL = folder.appendingPathComponent("Broken.pesto")
        try Data("not json".utf8).write(to: badURL)

        let library = try await MobileTestLibrary()
        await library.state.prepareCollectionImport(from: badURL)

        #expect(library.state.pendingCollectionImport == nil)
        #expect(library.state.notice?.isProblem == true)
    }

    @Test("acceptPendingCollectionImport works even after dismissPendingCollectionImport fires during dialog close")
    func whenAcceptedAfterDismissSignal_thenImportsSuccessfully() async throws {
        let source = try await MobileTestLibrary()
        let board = try #require(source.state.addCollection(named: "Work", existing: []))
        let clip = try await source.add("Deploy key note")
        source.state.moveToCollection(clip, collectionID: board.id)

        let exportedURL = try #require(await source.state.exportCollection(board))
        defer { ShareFile.remove(exportedURL) }

        let destination = try await MobileTestLibrary()
        await destination.state.prepareCollectionImport(from: exportedURL)
        let pending = try #require(destination.state.pendingCollectionImport)

        destination.state.dismissPendingCollectionImport(pending)
        destination.state.acceptPendingCollectionImport(pending)
        await destination.state.collectionImportTask?.value
        try await destination.refreshed()

        #expect(destination.state.pendingCollectionImport == nil)
        #expect(destination.store.items.map(\.displayPreviewText).contains("Deploy key note"))
    }

    @Test("opening a symlink to a valid .pesto file previews and imports cleanly")
    func whenSymlinkCollectionFileOpened_thenImportsCleanly() async throws {
        let source = try await MobileTestLibrary()
        let board = try #require(source.state.addCollection(named: "Links", existing: []))
        let clip = try await source.add("Linked clip")
        source.state.moveToCollection(clip, collectionID: board.id)

        let exportedURL = try #require(await source.state.exportCollection(board))
        defer { ShareFile.remove(exportedURL) }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("symlink-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let symlinkURL = folder.appendingPathComponent("Linked.pesto")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: exportedURL)

        let destination = try await MobileTestLibrary()
        #expect(destination.state.open(symlinkURL) == .shown)
        await destination.state.collectionImportPreparationTask?.value

        #expect(destination.state.pendingCollectionImport?.preview.name == "Links")
    }

    @Test("replacing a pending collection import cleans up the previous staged file")
    func whenSecondCollectionPrepared_thenReplacesFirstCleanly() async throws {
        let source = try await MobileTestLibrary()
        let firstBoard = try #require(source.state.addCollection(named: "First", existing: []))
        let firstClip = try await source.add("First note")
        source.state.moveToCollection(firstClip, collectionID: firstBoard.id)

        let secondBoard = try #require(source.state.addCollection(named: "Second", existing: [firstBoard]))
        let secondClip = try await source.add("Second note")
        source.state.moveToCollection(secondClip, collectionID: secondBoard.id)

        let firstURL = try #require(await source.state.exportCollection(firstBoard))
        let secondURL = try #require(await source.state.exportCollection(secondBoard))
        defer {
            ShareFile.remove(firstURL)
            ShareFile.remove(secondURL)
        }

        let destination = try await MobileTestLibrary()
        await destination.state.prepareCollectionImport(from: firstURL)
        let firstPending = try #require(destination.state.pendingCollectionImport)
        let firstStaged = try #require(firstPending.cleanupURL)

        await destination.state.prepareCollectionImport(from: secondURL)
        let secondPending = try #require(destination.state.pendingCollectionImport)
        let secondStaged = try #require(secondPending.cleanupURL)

        #expect(secondPending.preview.name == "Second")
        #expect(!FileManager.default.fileExists(atPath: firstStaged.path))
        #expect(FileManager.default.fileExists(atPath: secondStaged.path))

        destination.state.cancelPendingCollectionImport()
    }

    @Test("locked state refuses exportCollection, exportHistoryJSON, and importHistoryJSON")
    func whenLocked_thenExportAndJSONImportRefuse() async throws {
        let lock = MobileHistoryLock(
            authenticator: StubUserAuthenticator(available: true, grants: true),
            grace: AuthenticationGrace(),
            isEnabled: { true }
        )
        let library = try await MobileTestLibrary(lock: lock)
        let board = try #require(library.state.addCollection(named: "Private", existing: []))
        let clip = try await library.add("Keep private")
        library.state.moveToCollection(clip, collectionID: board.id)

        let sampleJSON = FileManager.default.temporaryDirectory
            .appendingPathComponent("locked-import-\(UUID().uuidString).json")
        try Data("[]".utf8).write(to: sampleJSON)
        defer { try? FileManager.default.removeItem(at: sampleJSON) }

        lock.lock()
        #expect(await library.state.exportCollection(board) == nil)
        #expect(await library.state.exportHistoryJSON() == nil)
        await library.state.importHistoryJSON(from: sampleJSON)
        #expect(library.state.notice == nil)
    }
}
