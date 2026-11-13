// SPDX-License-Identifier: MIT
import AppKit
import PestoCore

@MainActor
extension AppDelegate {
    /// The one way a collection file is imported from the shelf and from Settings. The shelf closes first: an open
    /// panel
    /// that took the keyboard would close it under the panel.
    func requestCollectionImport() {
        guard appState.isOverlayVisible else {
            runCollectionImportPanel()
            return
        }
        appState.close(.afterHide { [weak self] in self?.runCollectionImportPanel() })
    }

    private func runCollectionImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = CollectionFileType.importableTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Self.collectionImports.enqueue { await self.importCollectionFile(at: url, asksFirst: false) }
    }

    /// A `.pesto` file handed to the app by Finder, AirDrop or a double click. Nothing is imported until the person
    /// says yes.
    func openCollectionFile(_ url: URL) {
        switch CollectionFileType.openVerdict(for: url) {
        case .notACollectionFile: return
        case .tooLarge: presentCollectionImportProblem(String(localized: "That file is too large to be a collection."))
        case .accept: Self.collectionImports.enqueue { await self.importCollectionFile(at: url, asksFirst: true) }
        }
    }

    /// Files opened together are imported one after another, so no two questions or results are on screen at once.
    private static let collectionImports = CollectionImportQueue()

    private func importCollectionFile(at url: URL, asksFirst: Bool) async {
        guard AppDefaults.store.value(for: Setting.hasOnboarded), !appState.isEncryptionKeyUnresolved else {
            presentCollectionImportProblem(
                String(localized: "Finish setting up Pesto first, then open the file again.")
            )
            return
        }
        guard let container = appState.historyContainer, let storage = appState.storageService else {
            presentCollectionImportProblem(String(localized: "Pesto isn\u{2019}t ready yet. Try again in a moment."))
            return
        }
        let exporter = HistoryExporter(modelContainer: container)
        let preview: CollectionImportPreview
        do {
            preview = try await exporter.importPreview(
                fromFile: url, policy: RetentionPolicy.fromDefaults(AppDefaults.store)
            )
        } catch {
            Self.logger.error("Collection file unreadable: \(error.localizedDescription, privacy: .public)")
            presentCollectionImportProblem(CollectionTransferText.unreadable(error))
            return
        }
        // Asked before anything else: a file opened from Finder is never imported unasked, and one that would push the
        // person's own clips out of the history is never imported without saying so.
        if asksFirst || preview.wouldRemove > 0, !confirmCollectionImport(preview) { return }
        guard await ProtectedAction.permitted(reason: String(localized: "Import a collection")) else {
            presentCollectionImportProblem(
                String(localized: "Pesto is locked. Unlock your history, then open the file again.")
            )
            return
        }
        do {
            let result = try await exporter.importCollection(
                fromFile: url, storage: storage, exclusionRules: currentExclusionRules(),
                undoHistory: appState.undoHistory
            )
            presentCollectionImportResult(result)
        } catch {
            Self.logger.error("Collection import failed: \(error.localizedDescription, privacy: .public)")
            presentCollectionImportProblem(String(localized: "Pesto couldn\u{2019}t import that file."))
        }
    }

    private func confirmCollectionImport(_ preview: CollectionImportPreview) -> Bool {
        let alert = NSAlert()
        alert.messageText = CollectionTransferText.importQuestion(name: preview.name)
        alert.informativeText = CollectionTransferText.importDetail(preview)
        alert.addButton(withTitle: String(localized: "Import"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentCollectionImportResult(_ result: CollectionImportResult) {
        let alert = NSAlert()
        alert.messageText = CollectionTransferText.imported(result)
        alert.informativeText = CollectionTransferText.importDetail(result)
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }

    private func presentCollectionImportProblem(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn\u{2019}t import the collection.")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }
}

@MainActor
final class CollectionImportQueue {
    private var pending: [() async -> Void] = []
    private var isRunning = false

    func enqueue(_ job: @escaping () async -> Void) {
        pending.append(job)
        guard !isRunning else { return }
        isRunning = true
        Task { @MainActor in
            while !pending.isEmpty {
                await pending.removeFirst()()
            }
            isRunning = false
        }
    }
}
