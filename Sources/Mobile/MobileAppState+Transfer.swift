// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore
import SwiftData

/// Export and import on iPhone and iPad: `.pesto` collections (ADR 0045) and history JSON parity with macOS.
extension MobileAppState {
    private static let transferLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "MobileTransfer")

    struct PendingCollectionImport: Equatable, Identifiable {
        let id = UUID()
        let url: URL
        let preview: CollectionImportPreview
        let cleanupURL: URL?
    }

    static var importStagingDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pesto-import", isDirectory: true)
    }

    static func clearImportStaging() {
        ShareFile.removeAll(in: importStagingDirectory)
    }

    private static func stageImportFile(_ data: Data, name: String) throws -> URL {
        try ShareFile.write(
            data,
            fileName: name.isEmpty ? CollectionFilePolicy.defaultName : name,
            fileExtension: CollectionFileType.fileExtension,
            in: importStagingDirectory
        )
    }

    private static func removeImportStagedFile(_ url: URL) {
        if ShareFile.owns(url, in: importStagingDirectory) {
            ShareFile.remove(url)
        }
    }

    func exportCollection(_ board: Pinboard) async -> URL? {
        guard !isHistoryLockedNow(), let container = historyContainer,
              await confirmsLockedCollectionAction(board.id, reason: Self.exportLockedReason) else { return nil }
        let boardID = board.id
        let boardName = board.name
        var exportedURL: URL?
        await reportAsync("Couldn\u{2019}t export the collection.") {
            let exporter = HistoryExporter(modelContainer: container)
            let file = try await exporter.exportCollectionFile(id: boardID)
            guard !Task.isCancelled, !isHistoryLockedNow() else { return }
            let name = CollectionFilePolicy.sanitizedName(boardName)
            let url = try ShareFile.write(
                file.data, fileName: name.isEmpty ? CollectionFilePolicy.defaultName : name,
                fileExtension: CollectionFileType.fileExtension
            )
            guard !Task.isCancelled, !isHistoryLockedNow() else {
                ShareFile.remove(url)
                return
            }
            exportedURL = url
            if file.skipped > 0 {
                let skipped = CollectionTransferText.skippedLines(
                    tooLarge: file.skippedTooLarge, sensitive: file.skippedSensitive,
                    unreadable: file.skippedUnreadable, files: file.skippedFiles,
                    overLimit: file.skippedOverLimit, pictures: file.skippedPictures
                )
                let summary = skipped.isEmpty
                    ? CollectionTransferText.exported(file.exported)
                    : "\(CollectionTransferText.exported(file.exported)). " +
                    skipped.replacingOccurrences(of: "\n", with: " ")
                tell(summary)
            }
        }
        return exportedURL
    }

    func exportHistoryJSON() async -> URL? {
        guard !isHistoryLockedNow(), let container = historyContainer else { return nil }
        var exportedURL: URL?
        await reportAsync("Couldn\u{2019}t export the history.") {
            let data = try await HistoryExporter(modelContainer: container).export()
            guard !Task.isCancelled, !isHistoryLockedNow() else { return }
            let url = try ShareFile.write(data, fileName: "pesto-history", fileExtension: "json")
            guard !Task.isCancelled, !isHistoryLockedNow() else {
                ShareFile.remove(url)
                return
            }
            exportedURL = url
        }
        return exportedURL
    }

    func importHistoryJSON(from url: URL) async {
        guard !isHistoryLockedNow(), let container = historyContainer else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try await Task.detached { try Self.readCoordinatedContents(of: url) }.value
            guard !Task.isCancelled, !isHistoryLockedNow() else { return }
            let count = try await HistoryExporter(modelContainer: container).importRecords(from: data)
            guard !Task.isCancelled, !isHistoryLockedNow() else { return }
            if count > 0 {
                writeQuickInsert()
                await writeWidget()
            }
            tell(count == 0 ? String(localized: "Nothing new.") : String(localized: "\(count) clips imported."))
        } catch is CancellationError {
            return
        } catch {
            guard !isHistoryLockedNow() else { return }
            Self.transferLogger.error("History JSON import failed: \(error.localizedDescription, privacy: .public)")
            tell(
                String(localized: "Couldn\u{2019}t import that file. Check that it is a Pesto export."),
                isProblem: true
            )
        }
    }

    @discardableResult
    func openCollectionFile(_ url: URL) -> Bool {
        guard url.isFileURL,
              CollectionFileType.importableExtensions.contains(url.pathExtension.lowercased()) else
        {
            return false
        }
        boot()
        let scoped = url.startAccessingSecurityScopedResource()
        if isHistoryLockedNow() {
            heldSecurityScopedURL?.stopAccessingSecurityScopedResource()
            heldSecurityScopedURL = scoped ? url : nil
            heldLink = url
            return true
        }
        collectionImportPreparationTask?.cancel()
        collectionImportPreparationTask = Task { [weak self] in
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await self?.prepareCollectionImport(from: url, alreadyScoped: scoped)
        }
        return true
    }

    func prepareCollectionImport(from url: URL, alreadyScoped: Bool = false) async {
        guard !isHistoryLockedNow(), let container = historyContainer else { return }
        let localScoped = alreadyScoped ? false : url.startAccessingSecurityScopedResource()
        defer { if localScoped { url.stopAccessingSecurityScopedResource() } }

        var tempURL: URL?
        do {
            let data = try await Task.detached { try Self.readCoordinatedContents(of: url) }.value
            guard !Task.isCancelled, !isHistoryLockedNow() else { return }
            let stem = url.deletingPathExtension().lastPathComponent
            let staged = try Self.stageImportFile(data, name: stem)
            tempURL = staged
            let preview = try await HistoryExporter(modelContainer: container).importPreview(
                fromFile: staged, policy: retentionPolicy()
            )
            guard !Task.isCancelled, !isHistoryLockedNow() else {
                Self.removeImportStagedFile(staged)
                return
            }
            if let existing = pendingCollectionImport {
                pendingCollectionImport = nil
                if let existingCleanup = existing.cleanupURL {
                    Self.removeImportStagedFile(existingCleanup)
                }
                await Task.yield()
                guard !Task.isCancelled, !isHistoryLockedNow() else {
                    Self.removeImportStagedFile(staged)
                    return
                }
            }
            pendingCollectionImport = PendingCollectionImport(url: staged, preview: preview, cleanupURL: staged)
        } catch is CancellationError {
            if let tempURL { Self.removeImportStagedFile(tempURL) }
        } catch {
            if let tempURL { Self.removeImportStagedFile(tempURL) }
            guard !isHistoryLockedNow() else { return }
            Self.transferLogger.error("Collection file unreadable: \(error.localizedDescription, privacy: .public)")
            tell(CollectionTransferText.unreadable(error), isProblem: true)
        }
    }

    func confirmPendingCollectionImport() async {
        guard let pending = pendingCollectionImport else { return }
        await performCollectionImport(pending)
    }

    func acceptPendingCollectionImport(_ pending: PendingCollectionImport) {
        if pendingCollectionImport?.id == pending.id {
            pendingCollectionImport = nil
        }
        collectionImportTask?.cancel()
        collectionImportTask = Task { [weak self] in
            await self?.performCollectionImport(pending)
        }
    }

    private func performCollectionImport(_ pending: PendingCollectionImport) async {
        if pendingCollectionImport?.id == pending.id {
            pendingCollectionImport = nil
        }
        defer {
            if let cleanup = pending.cleanupURL {
                Self.removeImportStagedFile(cleanup)
            }
        }
        guard !Task.isCancelled, !isHistoryLockedNow(),
              let container = historyContainer, let storage = storageService else { return }
        let mark = storage.undoHistory.recordedCount
        do {
            let result = try await HistoryExporter(modelContainer: container).importCollection(
                fromFile: pending.url, storage: storage, exclusionRules: ExclusionRules.fromSettings(),
                undoHistory: undoHistory
            )
            guard !Task.isCancelled, !isHistoryLockedNow() else { return }
            if result.itemsImported > 0 {
                offerUndo(since: mark)
                writeQuickInsert()
                await writeWidget()
            }
            if result.itemsImported == 0, result.skipped > 0 || result.alreadyPresent > 0 {
                tell(CollectionTransferText.importDetail(result).replacingOccurrences(of: "\n", with: " "))
            } else if result.itemsImported > 0, result.skipped > 0 {
                tell(
                    "\(CollectionTransferText.imported(result)). " +
                        CollectionTransferText.importDetail(result).replacingOccurrences(of: "\n", with: " ")
                )
            } else {
                tell(CollectionTransferText.imported(result))
            }
        } catch is CancellationError {
            return
        } catch {
            guard !isHistoryLockedNow() else { return }
            Self.transferLogger.error("Collection import failed: \(error.localizedDescription, privacy: .public)")
            tell(String(localized: "Couldn\u{2019}t import the collection."), isProblem: true)
        }
    }

    func dismissPendingCollectionImport(_ pending: PendingCollectionImport?) {
        guard let pending, pendingCollectionImport?.id == pending.id else { return }
        pendingCollectionImport = nil
    }

    func cancelPendingCollectionImport() {
        collectionImportPreparationTask?.cancel()
        collectionImportPreparationTask = nil
        collectionImportTask?.cancel()
        collectionImportTask = nil
        if let cleanup = pendingCollectionImport?.cleanupURL {
            Self.removeImportStagedFile(cleanup)
        }
        pendingCollectionImport = nil
    }

    private nonisolated static func readCoordinatedContents(of url: URL) throws -> Data {
        var coordinatorError: NSError?
        var outcome: Result<Data, any Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url, options: .withoutChanges, error: &coordinatorError
        ) { coordinatedURL in
            switch CollectionFileType.openVerdict(for: coordinatedURL) {
            case .notACollectionFile:
                outcome = .failure(HistoryExporter.ImportError.notARegularFile)
            case .tooLarge:
                outcome = .failure(HistoryExporter.ImportError.fileTooLarge)
            case .accept:
                outcome = Result { try HistoryExporter.boundedContents(of: coordinatedURL) }
            }
        }
        if let coordinatorError { throw coordinatorError }
        return try outcome?.get() ?? HistoryExporter.boundedContents(of: url)
    }
}
