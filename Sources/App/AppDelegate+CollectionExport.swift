// SPDX-License-Identifier: MIT
import AppKit
import PestoCore
import SwiftData

@MainActor
extension AppDelegate {
    /// The one way a collection is exported, from its menu on the shelf and from Settings. The shelf closes first: a
    /// save panel that took the keyboard would close it under the panel.
    func requestCollectionExport(id: UUID) {
        guard appState.isOverlayVisible else {
            runCollectionExport(id: id)
            return
        }
        appState.close(.afterHide { [weak self] in self?.runCollectionExport(id: id) })
    }

    private func runCollectionExport(id: UUID) {
        guard let container = appState.historyContainer else { return }
        let name = (try? container.mainContext.fetch(
            FetchDescriptor<Pinboard>(predicate: #Predicate { $0.id == id })
        ))?.first?.name ?? String(localized: "Collection")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).\(CollectionFileType.fileExtension)"
        panel.allowedContentTypes = [CollectionFileType.utType]
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                let file = try await HistoryExporter(modelContainer: container).writeCollection(id: id, to: url)
                if file.skipped > 0 { presentCollectionExportSkips(file: file) }
            } catch {
                Self.logger.error("Collection export failed: \(error.localizedDescription, privacy: .public)")
                presentCollectionExportFailure(name: name)
            }
        }
    }

    private func presentCollectionExportFailure(name: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn\u{2019}t export \u{201C}\(name)\u{201D}.")
        alert
            .informativeText =
            String(localized: "Pesto couldn\u{2019}t write the file. Choose another folder and try again.")
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }

    private func presentCollectionExportSkips(file: CollectionExportFile) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = CollectionTransferText.exported(file.exported)
        alert.informativeText = CollectionTransferText.skippedLines(
            tooLarge: file.skippedTooLarge, sensitive: file.skippedSensitive, unreadable: file.skippedUnreadable,
            files: file.skippedFiles, overLimit: file.skippedOverLimit,
            pictures: file.skippedPictures
        )
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alert.runModal()
    }
}
