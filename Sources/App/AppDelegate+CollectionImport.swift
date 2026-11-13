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
        importCollectionFile(at: url, asksFirst: false)
    }

    /// A `.pesto` file handed to the app by Finder, AirDrop or a double click. Nothing is imported until the person
    /// says yes.
    func openCollectionFile(_ url: URL) {
        switch CollectionFileType.openVerdict(for: url) {
        case .notACollectionFile: return
        case .tooLarge: presentCollectionImportProblem(String(localized: "That file is too large to be a collection."))
        case .accept: importCollectionFile(at: url, asksFirst: true)
        }
    }

    private func importCollectionFile(at url: URL, asksFirst: Bool) {
        guard let container = appState.historyContainer, let storage = appState.storageService else { return }
        Task { @MainActor in
            guard await ProtectedAction.permitted(reason: String(localized: "Import a collection")) else {
                presentCollectionImportProblem(
                    String(localized: "Pesto is locked. Unlock your history, then open the file again.")
                )
                return
            }
            let summary: CollectionFileType.Summary
            do {
                summary = try CollectionFileType.summary(ofFile: url)
            } catch {
                Self.logger.error("Collection file unreadable: \(error.localizedDescription, privacy: .public)")
                presentCollectionImportProblem(String(localized: "That file is not a Pesto collection."))
                return
            }
            if asksFirst, !confirmCollectionImport(summary) { return }
            do {
                let result = try await HistoryExporter(modelContainer: container).importCollection(
                    fromFile: url, storage: storage, exclusionRules: currentExclusionRules(),
                    undoHistory: appState.undoHistory
                )
                presentCollectionImportResult(result, name: summary.name)
            } catch {
                Self.logger.error("Collection import failed: \(error.localizedDescription, privacy: .public)")
                presentCollectionImportProblem(String(localized: "Pesto couldn\u{2019}t import that file."))
            }
        }
    }

    private func confirmCollectionImport(_ summary: CollectionFileType.Summary) -> Bool {
        let alert = NSAlert()
        alert.messageText = CollectionTransferText.importQuestion(name: summary.name)
        alert.informativeText = CollectionTransferText.importDetail(clipCount: summary.clipCount)
        alert.addButton(withTitle: String(localized: "Import"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentCollectionImportResult(_ result: CollectionImportResult, name: String) {
        let alert = NSAlert()
        alert.messageText = CollectionTransferText.imported(result)
        alert.informativeText = CollectionTransferText.importDetail(result, name: name)
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
